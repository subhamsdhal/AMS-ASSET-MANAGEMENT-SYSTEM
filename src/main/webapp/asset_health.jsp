<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.SettingsDAO"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    static class HealthRow {
        int assetId;
        int score;
        int maintenanceCount;
        int ageDays;
        int warrantyDaysLeft;
        int verificationAgeDays;
        double maintenanceCost;
        String assetCode;
        String assetName;
        String categoryName;
        String departmentName;
        String assetStatus;
        String conditionStatus;
        String serviceStatus;
        String lastMaintenance;
        String recommendation;
        String reason;
        String riskClass;
    }

    private String safeText(Object value) {
        if (value == null || String.valueOf(value).trim().isEmpty()) {
            return "N/A";
        }

        return String.valueOf(value).trim()
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

    private int intValue(ResultSet rs, String column) {
        try {
            return rs.getInt(column);
        } catch (Exception e) {
            return 0;
        }
    }

    private Map<String, Integer> loadHealthWeights() {
        Map<String, Integer> weights = new HashMap<String, Integer>();
        String sql = "SELECT setting_key, setting_value FROM system_settings WHERE setting_group = 'ASSET_HEALTH'";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                try {
                    weights.put(rs.getString("setting_key"), Integer.parseInt(rs.getString("setting_value")));
                } catch (Exception ignored) {
                }
            }

        } catch (Exception e) {
            // Defaults below keep the page usable even before the Phase 15 migration is applied.
        }

        return weights;
    }

    private int weight(Map<String, Integer> weights, String key, int fallback) {
        Integer value = weights.get(key);
        return value == null ? fallback : Math.max(0, value);
    }

    /**
     * Fault (dead setting, fixed): Settings > Operations > Asset Health
     * exposes five category weight fields (age/maintenance/warranty/
     * condition/verification - SettingsDAO.getHealthWeight*(), correctly
     * saved and read back via the generic SettingsDAO.get()/set() key-value
     * store) plus an on/off toggle (SettingsDAO.isHealthScoreEnabled()).
     * Neither was ever read from this file - the score was computed with
     * fixed, hardcoded penalties regardless of what Settings showed, and
     * the toggle had no effect on whether scoring ran at all. The five
     * category multipliers below (categoryWeight / thatCategory's OWN
     * default weight, so leaving every field at its default reproduces the
     * exact scoring this page already had) now actually scale each
     * penalty's contribution, on top of - not instead of - the existing
     * per-penalty ams.health.penalty.* override mechanism (loadHealthWeights()
     * above), which continues to work exactly as before for anyone using it.
     */
    private int calculateScore(String status, String condition, String service, int ageDays,
            int warrantyDaysLeft, int maintenanceCount, double maintenanceCost, int verificationAgeDays,
            Map<String, Integer> weights, double conditionMultiplier, double warrantyMultiplier,
            double maintenanceMultiplier, double ageMultiplier, double verificationMultiplier) {

        int score = 100;

        if ("DISPOSED".equalsIgnoreCase(status) || "LOST".equalsIgnoreCase(status)) {
            return 0;
        }

        if ("UNDER_MAINTENANCE".equalsIgnoreCase(status)) {
            score -= scaled(weight(weights, "ams.health.penalty.status.under_maintenance", 25), conditionMultiplier);
        } else if ("DAMAGED".equalsIgnoreCase(status)) {
            score -= scaled(weight(weights, "ams.health.penalty.status.damaged", 35), conditionMultiplier);
        }

        if ("DAMAGED".equalsIgnoreCase(condition)) {
            score -= scaled(weight(weights, "ams.health.penalty.condition.damaged", 20), conditionMultiplier);
        } else if ("NEEDS_REPAIR".equalsIgnoreCase(condition)) {
            score -= scaled(weight(weights, "ams.health.penalty.condition.needs_repair", 15), conditionMultiplier);
        }

        if ("SCRAP_RECOMMENDED".equalsIgnoreCase(service)) {
            score -= scaled(weight(weights, "ams.health.penalty.service.scrap_recommended", 45), conditionMultiplier);
        } else if ("UNSERVICEABLE".equalsIgnoreCase(service)) {
            score -= scaled(weight(weights, "ams.health.penalty.service.unserviceable", 35), conditionMultiplier);
        } else if ("UNDER_REPAIR".equalsIgnoreCase(service)) {
            score -= scaled(weight(weights, "ams.health.penalty.service.under_repair", 20), conditionMultiplier);
        } else if ("NEEDS_ATTENTION".equalsIgnoreCase(service)) {
            score -= scaled(weight(weights, "ams.health.penalty.service.needs_attention", 15), conditionMultiplier);
        }

        if (warrantyDaysLeft < 0) {
            score -= scaled(weight(weights, "ams.health.penalty.warranty.expired", 10), warrantyMultiplier);
        } else if (warrantyDaysLeft <= 60) {
            score -= scaled(weight(weights, "ams.health.penalty.warranty.expiring_soon", 5), warrantyMultiplier);
        }

        if (maintenanceCount >= 4) {
            score -= scaled(weight(weights, "ams.health.penalty.maintenance.high_frequency", 18), maintenanceMultiplier);
        } else if (maintenanceCount >= 2) {
            score -= scaled(weight(weights, "ams.health.penalty.maintenance.medium_frequency", 10), maintenanceMultiplier);
        } else if (maintenanceCount == 1) {
            score -= scaled(weight(weights, "ams.health.penalty.maintenance.low_frequency", 4), maintenanceMultiplier);
        }

        if (maintenanceCost >= 50000) {
            score -= scaled(weight(weights, "ams.health.penalty.cost.high", 12), maintenanceMultiplier);
        } else if (maintenanceCost >= 10000) {
            score -= scaled(weight(weights, "ams.health.penalty.cost.medium", 6), maintenanceMultiplier);
        }

        if (ageDays >= 2555) {
            score -= scaled(weight(weights, "ams.health.penalty.age.old", 10), ageMultiplier);
        } else if (ageDays >= 1460) {
            score -= scaled(weight(weights, "ams.health.penalty.age.mature", 5), ageMultiplier);
        }

        if (verificationAgeDays >= 365) {
            score -= scaled(weight(weights, "ams.health.penalty.verification.overdue", 8), verificationMultiplier);
        }

        return Math.max(0, Math.min(100, score));
    }

    /** Rounds to the nearest point - a fractional penalty (e.g. a 0.5x weight) would otherwise silently truncate toward zero every time. */
    private int scaled(int basePenalty, double multiplier) {
        return (int) Math.round(basePenalty * multiplier);
    }

    private String recommendationFor(int score, String status, String service) {
        if ("DISPOSED".equalsIgnoreCase(status) || "LOST".equalsIgnoreCase(status)) {
            return "Dispose Candidate";
        }

        if (score >= 85) {
            return "Continue Using";
        }

        if (score >= 70) {
            return "Schedule Maintenance";
        }

        if (score >= 45) {
            return "Repair Recommended";
        }

        if ("SCRAP_RECOMMENDED".equalsIgnoreCase(service) || score < 30) {
            return "Dispose Candidate";
        }

        return "Replace Soon";
    }

    private String riskClassFor(int score) {
        if (score >= 85) {
            return "good";
        }

        if (score >= 70) {
            return "watch";
        }

        if (score >= 45) {
            return "repair";
        }

        return "critical";
    }

    private String reasonFor(HealthRow row) {
        List<String> reasons = new ArrayList<String>();

        if (!"AVAILABLE".equalsIgnoreCase(row.assetStatus) && !"ALLOCATED".equalsIgnoreCase(row.assetStatus)) {
            reasons.add(cleanLabel(row.assetStatus));
        }

        if (!"GOOD".equalsIgnoreCase(row.conditionStatus)) {
            reasons.add(cleanLabel(row.conditionStatus));
        }

        if (!"SERVICEABLE".equalsIgnoreCase(row.serviceStatus)) {
            reasons.add(cleanLabel(row.serviceStatus));
        }

        if (row.maintenanceCount >= 2) {
            reasons.add(row.maintenanceCount + " maintenance records");
        }

        if (row.warrantyDaysLeft < 0) {
            reasons.add("warranty expired");
        } else if (row.warrantyDaysLeft <= 60) {
            reasons.add("warranty expiring soon");
        }

        if (row.verificationAgeDays >= 365) {
            reasons.add("verification overdue");
        }

        if (reasons.isEmpty()) {
            return "No immediate risk signal";
        }

        return String.join(", ", reasons);
    }
%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    boolean allowed = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "DEPARTMENT_HEAD".equals(role)
            || "AUDITOR".equals(role);

    if (!allowed) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    // Fault (dead setting, fixed): Settings > Operations > Asset Health has
    // an on/off toggle (SettingsDAO.isHealthScoreEnabled()) that was saved
    // and displayed correctly but never actually checked anywhere - this
    // page computed and showed scores regardless of it. Gated here instead
    // of hiding the nav link, so a role that lands here directly (or via an
    // old bookmark) gets an honest explanation rather than a page that
    // silently ignores an admin's own setting.
    boolean healthScoringEnabled = SettingsDAO.isHealthScoreEnabled();

    // Fault (dead setting, fixed): the five category weight fields on that
    // same Settings tab (age/maintenance/warranty/condition/verification)
    // were correctly saved and read back by SettingsDAO, just never
    // consulted by calculateScore() below - scoring always used fixed,
    // hardcoded penalties no matter what Settings showed. Each multiplier
    // is (configured weight / that category's own default weight), so
    // leaving every field at its default reproduces this page's original
    // scoring exactly; changing one scales only that category's penalties.
    double conditionMultiplier    = SettingsDAO.getHealthWeightCondition()    / 25.0;
    double warrantyMultiplier     = SettingsDAO.getHealthWeightWarranty()     / 20.0;
    double maintenanceMultiplier  = SettingsDAO.getHealthWeightMaintenance()  / 25.0;
    double ageMultiplier          = SettingsDAO.getHealthWeightAge()         / 20.0;
    double verificationMultiplier = SettingsDAO.getHealthWeightVerification() / 10.0;

    List<HealthRow> rows = new ArrayList<HealthRow>();
    String errorMessage = "";
    Map<String, Integer> healthWeights = loadHealthWeights();

    String sql = "SELECT a.asset_id, a.asset_code, a.asset_name, "
            + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
            + "COALESCE(d.department_name, 'Unassigned') AS department_name, "
            + "COALESCE(a.asset_status, '') AS asset_status, "
            + "COALESCE(a.condition_status, '') AS condition_status, "
            + "COALESCE(a.service_status, '') AS service_status, "
            + "COALESCE(DATEDIFF(CURDATE(), a.purchase_date), 0) AS age_days, "
            + "COALESCE(DATEDIFF(a.warranty_expiry, CURDATE()), 9999) AS warranty_days_left, "
            + "COALESCE(DATEDIFF(CURDATE(), a.last_physical_verification_date), 9999) AS verification_age_days, "
            + "COALESCE(ml.maintenance_count, 0) AS maintenance_count, "
            + "COALESCE(ml.maintenance_cost, 0) AS maintenance_cost, "
            + "COALESCE(DATE_FORMAT(ml.last_maintenance, '%d %b %Y'), 'N/A') AS last_maintenance "
            + "FROM assets a "
            + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
            + "LEFT JOIN departments d ON a.department_id = d.department_id "
            + "LEFT JOIN ("
            + "    SELECT asset_id, COUNT(*) AS maintenance_count, COALESCE(SUM(cost), 0) AS maintenance_cost, MAX(maintenance_date) AS last_maintenance "
            + "    FROM maintenance_logs GROUP BY asset_id"
            + ") ml ON a.asset_id = ml.asset_id";

    try (Connection con = DBConnection.getConnection();
         PreparedStatement ps = healthScoringEnabled ? con.prepareStatement(sql) : null;
         ResultSet rs = healthScoringEnabled ? ps.executeQuery() : null) {

        while (healthScoringEnabled && rs.next()) {
            HealthRow row = new HealthRow();
            row.assetId = rs.getInt("asset_id");
            row.assetCode = rs.getString("asset_code");
            row.assetName = rs.getString("asset_name");
            row.categoryName = rs.getString("category_name");
            row.departmentName = rs.getString("department_name");
            row.assetStatus = rs.getString("asset_status");
            row.conditionStatus = rs.getString("condition_status");
            row.serviceStatus = rs.getString("service_status");
            row.ageDays = intValue(rs, "age_days");
            row.warrantyDaysLeft = intValue(rs, "warranty_days_left");
            row.verificationAgeDays = intValue(rs, "verification_age_days");
            row.maintenanceCount = intValue(rs, "maintenance_count");
            row.maintenanceCost = rs.getDouble("maintenance_cost");
            row.lastMaintenance = rs.getString("last_maintenance");
            row.score = calculateScore(row.assetStatus, row.conditionStatus, row.serviceStatus,
                    row.ageDays, row.warrantyDaysLeft, row.maintenanceCount, row.maintenanceCost,
                    row.verificationAgeDays, healthWeights, conditionMultiplier, warrantyMultiplier,
                    maintenanceMultiplier, ageMultiplier, verificationMultiplier);
            row.recommendation = recommendationFor(row.score, row.assetStatus, row.serviceStatus);
            row.riskClass = riskClassFor(row.score);
            row.reason = reasonFor(row);
            rows.add(row);
        }

    } catch (Exception e) {
        errorMessage = "A database error occurred while fetching health data.";
        application.log("Asset health score failed", e);
    }

    Collections.sort(rows, new Comparator<HealthRow>() {
        @Override
        public int compare(HealthRow one, HealthRow two) {
            return Integer.compare(one.score, two.score);
        }
    });

    int good = 0;
    int watch = 0;
    int repair = 0;
    int critical = 0;

    for (HealthRow row : rows) {
        if ("good".equals(row.riskClass)) {
            good++;
        } else if ("watch".equals(row.riskClass)) {
            watch++;
        } else if ("repair".equals(row.riskClass)) {
            repair++;
        } else {
            critical++;
        }
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Asset Health Score - IR-AMS</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <link rel="stylesheet" href="css/ir-glass.css?v=phase15">
    <link rel="stylesheet" href="css/ams-pro.css?v=phase15">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=phase15">
    <link rel="stylesheet" href="css/asset_health.css?v=28001">
</head>
<body class="railway-ui">
<div class="health-shell">
    <section class="health-hero">
        <h1>Asset Health Score</h1>
        <p>
            Rule-based predictive maintenance view generated from live MySQL asset, warranty, maintenance,
            condition and physical verification data. Scores are transparent and non-destructive.
        </p>
        <div class="health-actions">
            <a class="health-btn" href="analytics.jsp"><i class="fa-solid fa-chart-line"></i> Analytics</a>
            <a class="health-btn secondary" href="reports.jsp"><i class="fa-solid fa-file-excel"></i> Reports</a>
            <a class="health-btn secondary" href="assets.jsp"><i class="fa-solid fa-cubes"></i> Asset Register</a>
        </div>
    </section>

    <% if (!errorMessage.isEmpty()) { %>
        <div class="error-box">Unable to calculate health score: <%= safeText(errorMessage) %></div>
    <% } %>

    <% if (!healthScoringEnabled) { %>
        <div class="error-box">
            Asset Health Score is currently <strong>disabled</strong> in Settings.
            <% if ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) { %>
                <a href="settings.jsp?section=health">Enable it in Settings &rarr;</a>
            <% } else { %>
                Ask an Admin to enable it under Settings &gt; Operations &gt; Asset Health.
            <% } %>
        </div>
    <% } %>

    <section class="health-grid">
        <div class="health-card"><span>Healthy</span><strong><%= good %></strong></div>
        <div class="health-card"><span>Watch List</span><strong><%= watch %></strong></div>
        <div class="health-card"><span>Repair Recommended</span><strong><%= repair %></strong></div>
        <div class="health-card"><span>Replace / Dispose Risk</span><strong><%= critical %></strong></div>
    </section>

    <section class="health-panel">
        <table class="health-table" id="healthTable">
            <thead>
                <tr>
                    <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Score <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                    <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Asset <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                    <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Department <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                    <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                    <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">Maintenance <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                    <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Warranty <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                    <th onclick="sortTable(6)" style="cursor: pointer;" title="Click to sort">Recommendation <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                    <th onclick="sortTable(7)" style="cursor: pointer;" title="Click to sort">Reason <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                </tr>
            </thead>
            <tbody>
                <% if (rows.isEmpty()) { %>
                    <tr><td colspan="8"><%= healthScoringEnabled ? "No asset records found." : "Scoring is disabled - see notice above." %></td></tr>
                <% } else {
                    int shown = 0;
                    for (HealthRow row : rows) {
                        if (shown >= 100) {
                            break;
                        }
                        shown++;
                %>
                    <tr>
                        <td><span class="score-pill <%= safeText(row.riskClass) %>"><%= row.score %></span></td>
                        <td>
                            <strong><%= safeText(row.assetCode) %></strong><br>
                            <%= safeText(row.assetName) %><br>
                            <small><%= safeText(row.categoryName) %></small>
                        </td>
                        <td><%= safeText(row.departmentName) %></td>
                        <td>
                            <%= safeText(cleanLabel(row.assetStatus)) %><br>
                            <small><%= safeText(cleanLabel(row.conditionStatus)) %> / <%= safeText(cleanLabel(row.serviceStatus)) %></small>
                        </td>
                        <td>
                            <%= row.maintenanceCount %> records<br>
                            <small>Cost INR <%= String.format(Locale.ENGLISH, "%.2f", row.maintenanceCost) %></small><br>
                            <small>Last: <%= safeText(row.lastMaintenance) %></small>
                        </td>
                        <td>
                            <% if (row.warrantyDaysLeft == 9999) { %>
                                N/A
                            <% } else if (row.warrantyDaysLeft < 0) { %>
                                Expired <%= Math.abs(row.warrantyDaysLeft) %> days ago
                            <% } else { %>
                                <%= row.warrantyDaysLeft %> days left
                            <% } %>
                        </td>
                        <td><span class="rec-pill"><%= safeText(row.recommendation) %></span></td>
                        <td><%= safeText(row.reason) %></td>
                    </tr>
                <%  }
                } %>
            </tbody>
        </table>
    </section>
</div>
<script src="js/dashboard-actions.js?v=phase15"></script>
<script>
    var sortDirections = [true, true, true, true, true, true, true, true];
    function sortTable(columnIndex) {
        var table = document.getElementById("healthTable");
        if (!table) return;
        
        var tbody = table.querySelector("tbody");
        if (!tbody) return;
        
        var rows = Array.from(tbody.querySelectorAll("tr"));
        if (rows.length === 1 && rows[0].querySelector("td[colspan]")) return; // Empty records row

        var asc = sortDirections[columnIndex];
        sortDirections[columnIndex] = !asc;

        rows.sort(function(a, b) {
            var cellA = a.querySelectorAll("td")[columnIndex];
            var cellB = b.querySelectorAll("td")[columnIndex];

            if (!cellA || !cellB) return 0;
            
            var valA = cellA.innerText || cellA.textContent;
            var valB = cellB.innerText || cellB.textContent;
            
            valA = valA.trim().toLowerCase();
            valB = valB.trim().toLowerCase();
            
            // Numeric sorting for Score (col 0)
            if (columnIndex === 0) {
                valA = parseFloat(valA) || 0;
                valB = parseFloat(valB) || 0;
            }
            
            if (valA < valB) return asc ? -1 : 1;
            if (valA > valB) return asc ? 1 : -1;
            return 0;
        });

        rows.forEach(function(row) {
            tbody.appendChild(row);
        });
        
        var headers = table.querySelectorAll("thead th");
        headers.forEach(function(th, idx) {
            var icon = th.querySelector("i.fa-sort, i.fa-sort-up, i.fa-sort-down");
            if (icon) {
                icon.className = "fa-solid fa-sort";
                if (idx === columnIndex) {
                    icon.className = asc ? "fa-solid fa-sort-up" : "fa-solid fa-sort-down";
                }
            }
        });
    }
</script>
</body>
</html>
