<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DashboardDAO"%>
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
            && !"ASSET_MANAGER".equals(role)
            && !"DEPARTMENT_HEAD".equals(role)
            && !"AUDITOR".equals(role)) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    // Fault: DashboardDAO.getCount/getAssetStatusCount/getTotalAssetValue were all
    // extended (see dashboard.jsp) to take a department-scoping List<Integer> so
    // DEPARTMENT_HEAD users only see their own department's numbers - this page was
    // never updated to match, so it failed to even compile (JasperException) on
    // every single visit. Fix: read the same session "departmentIds" attribute
    // dashboard.jsp uses and pass it through identically, so DEPARTMENT_HEAD scoping
    // is honored here too instead of just being restored to a compiling-but-wrong
    // unscoped state.
    List<Integer> departmentIds = (List<Integer>) session.getAttribute("departmentIds");

    DashboardDAO dao = new DashboardDAO();

    int totalAssets = dao.getCount("assets", departmentIds);
    int totalEmployees = dao.getCount("employees", departmentIds);
    int totalRequests = dao.getCount("asset_requests", departmentIds);
    int totalReturns = dao.getCount("asset_returns", departmentIds);
    int totalMaintenance = dao.getCount("maintenance_logs", departmentIds);

    int availableAssets = dao.getAssetStatusCount("AVAILABLE", departmentIds);
    int allocatedAssets = dao.getAssetStatusCount("ALLOCATED", departmentIds);
    int underMaintenanceAssets = dao.getAssetStatusCount("UNDER_MAINTENANCE", departmentIds);
    int disposedAssets = dao.getAssetStatusCount("DISPOSED", departmentIds);

    double totalAssetValue = dao.getTotalAssetValue(departmentIds);
    double availabilityRate = totalAssets == 0 ? 0 : (availableAssets * 100.0 / totalAssets);
    double allocationRate = totalAssets == 0 ? 0 : (allocatedAssets * 100.0 / totalAssets);
    double maintenanceRate = totalAssets == 0 ? 0 : (underMaintenanceAssets * 100.0 / totalAssets);
    double disposalRate = totalAssets == 0 ? 0 : (disposedAssets * 100.0 / totalAssets);

    double avgAssetValue = totalAssets == 0 ? 0 : (totalAssetValue / totalAssets);

    double requestPressure = totalAssets == 0 ? 0 : (totalRequests * 100.0 / totalAssets);
    double returnRate = totalAssets == 0 ? 0 : (totalReturns * 100.0 / totalAssets);
    
    String systemHealth;

    if (maintenanceRate <= 10 && disposalRate <= 10) {
        systemHealth = "EXCELLENT";
    } else if (maintenanceRate <= 25 && disposalRate <= 20) {
        systemHealth = "STABLE";
    } else {
        systemHealth = "ATTENTION REQUIRED";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Analytics</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=request-return-report-inner-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=request-return-report-inner-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=request-return-report-inner-1">
<link rel="stylesheet" href="css/analytics.css?v=topbarfix1">
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>

<body class="railway-ui">

<div class="app">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">

                <jsp:include page="topbar.jsp" />
        <div class="main-scroll-content">
        <section class="analytics-hero">
            <h1>Advanced Analytics Center</h1>
            <p>
                Visual analysis of railway asset inventory, allocation movement, maintenance pressure,
                return trends and operational asset value.
            </p>

            <br>

            <div class="hero-pills">
                <div class="hero-pill"><i class="fa-solid fa-chart-line"></i> Trend Analytics</div>
                <div class="hero-pill"><i class="fa-solid fa-database"></i> Live MySQL Data</div>
                <div class="hero-pill"><i class="fa-solid fa-chart-pie"></i> Status Intelligence</div>
                <div class="hero-pill"><i class="fa-solid fa-brain"></i> Decision Support</div>
            </div>

            <div class="hero-pills" style="margin-top:14px;">
                <a class="hero-pill" href="asset_health.jsp" style="text-decoration:none;">
                    <i class="fa-solid fa-heart-pulse"></i> Asset Health Score
                </a>
                <a class="hero-pill" href="ams_copilot.jsp" style="text-decoration:none;">
                    <i class="fa-solid fa-comments"></i> AMS Copilot
                </a>
            </div>
        </section>

        <section class="kpi-grid">

            <div class="kpi-card">
                <div class="kpi-icon purple"><i class="fa-solid fa-boxes-stacked"></i></div>
                <h3>Total Assets</h3>
                <p><%= totalAssets %></p>
            </div>

            <div class="kpi-card">
                <div class="kpi-icon green"><i class="fa-solid fa-circle-check"></i></div>
                <h3>Available</h3>
                <p><%= availableAssets %></p>
            </div>

            <div class="kpi-card">
                <div class="kpi-icon blue"><i class="fa-solid fa-user-check"></i></div>
                <h3>Allocated</h3>
                <p><%= allocatedAssets %></p>
            </div>

            <div class="kpi-card">
                <div class="kpi-icon orange"><i class="fa-solid fa-wrench"></i></div>
                <h3>Maintenance</h3>
                <p><%= underMaintenanceAssets %></p>
            </div>

            <div class="kpi-card">
                <div class="kpi-icon red"><i class="fa-solid fa-trash"></i></div>
                <h3>Disposed</h3>
                <p><%= disposedAssets %></p>
            </div>

            <div class="kpi-card">
                <div class="kpi-icon pink"><i class="fa-solid fa-indian-rupee-sign"></i></div>
                <h3>Total Value</h3>
                <p>₹<%= String.format("%.0f", totalAssetValue) %></p>
            </div>

        </section>

        <section class="dashboard-grid">
            <div class="glass-panel">
            <h2>Operational Ratios</h2>

            <div class="mini-grid">

                <div class="mini-card">
                    <h4>Availability Rate</h4>
                    <p><%= String.format("%.1f", availabilityRate) %>%</p>
                </div>

                <div class="mini-card">
                    <h4>Allocation Rate</h4>
                    <p><%= String.format("%.1f", allocationRate) %>%</p>
                </div>

                <div class="mini-card">
                    <h4>Maintenance Load</h4>
                    <p><%= String.format("%.1f", maintenanceRate) %>%</p>
                </div>

                <div class="mini-card">
                    <h4>Return Rate</h4>
                    <p><%= String.format("%.1f", returnRate) %>%</p>
                </div>

                <div class="mini-card">
                    <h4>Avg Asset Value</h4>
                    <p>₹<%= String.format("%.0f", avgAssetValue) %></p>
                </div>

                <div class="mini-card">
                    <h4>System Health</h4>
                    <p><%= systemHealth %></p>
                </div>

            </div>
        </div>
            
            <div class="glass-panel" style="display: flex; flex-direction: column; align-items: center; justify-content: center;">
                <h2 style="width: 100%;">Asset Status Distribution</h2>
                <div style="width: 80%; max-width: 300px; padding-bottom: 20px;">
                    <canvas id="statusChart"></canvas>
                </div>
            </div>

            <div class="glass-panel">
                <h2>System Intelligence</h2>

                <div class="audit-stream">
                    <div class="audit-item">
                        <div class="audit-icon green"><i class="fa-solid fa-check"></i></div>
                        <div>
                            <h4>Inventory synchronized</h4>
                            <p>Asset status analytics are live.</p>
                        </div>
                    </div>

                    <div class="audit-item">
                        <div class="audit-icon blue"><i class="fa-solid fa-chart-line"></i></div>
                        <div>
                            <h4>Analytics ready</h4>
                            <p>Reports are generated from database values.</p>
                        </div>
                    </div>
                </div>
            </div>

        </section>
    </div>
    </main>

</div>

<script src="js/topbar-search.js?v=request-return-report-inner-1"></script>
<script src="js/user-dropdown.js?v=request-return-report-inner-1"></script>
<script src="js/sidebar-role.js?v=request-return-report-inner-1"></script>
<script src="js/ir-body-watermark.js?v=request-return-report-inner-1"></script>
<script src="js/dashboard-actions.js?v=request-return-report-inner-1"></script>

<script>
    document.addEventListener("DOMContentLoaded", function() {
        var ctx = document.getElementById('statusChart').getContext('2d');
        var statusChart = new Chart(ctx, {
            type: 'pie',
            data: {
                labels: ['Available', 'Allocated', 'Maintenance', 'Disposed'],
                datasets: [{
                    data: [<%= availableAssets %>, <%= allocatedAssets %>, <%= underMaintenanceAssets %>, <%= disposedAssets %>],
                    backgroundColor: [
                        'rgba(34, 197, 94, 0.8)',   // Green
                        'rgba(59, 130, 246, 0.8)',  // Blue
                        'rgba(249, 115, 22, 0.8)',  // Orange
                        'rgba(239, 68, 68, 0.8)'    // Red
                    ],
                    borderColor: '#ffffff',
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            font: { family: 'Georgia, serif', size: 13 },
                            color: '#18366f'
                        }
                    }
                }
            }
        });
    });
</script>

</body>
</html>
