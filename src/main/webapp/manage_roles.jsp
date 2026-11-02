<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.RoleIdResolver"%>

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

    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "-";
        }

        return safeValue(value);
    }

    private String normalizeRole(String roleName) {
        if (roleName == null) {
            return "";
        }

        return roleName.trim().toUpperCase().replace(" ", "_");
    }

    private String roleDisplay(String roleName) {
        if (roleName == null) {
            return "-";
        }

        return roleName.replace("_", " ");
    }

    private String roleIcon(String roleName) {
        String role = normalizeRole(roleName);

        if ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) {
            return "fa-user-tie";
        }

        if ("ASSET_MANAGER".equals(role)) {
            return "fa-boxes-stacked";
        }

        if ("DEPARTMENT_HEAD".equals(role)) {
            return "fa-user-shield";
        }

        if ("AUDITOR".equals(role)) {
            return "fa-clipboard-check";
        }

        if ("EMPLOYEE".equals(role)) {
            return "fa-user";
        }

        return "fa-circle-user";
    }

    private String statusBadge(String status) {
        if ("ACTIVE".equalsIgnoreCase(status)) {
            return "<span class='status-pill active-status'><i class='fa-solid fa-circle-check'></i> ACTIVE</span>";
        }

        return "<span class='status-pill inactive-status'><i class='fa-solid fa-circle-xmark'></i> INACTIVE</span>";
    }

    private String rolePurpose(String roleName) {
        String role = normalizeRole(roleName);

        if ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) {
            return "Complete control over users, settings, reports, backup, restore and audit operations.";
        }

        if ("ASSET_MANAGER".equals(role)) {
            return "Manages asset registration, category, vendor, allocation, return and maintenance operations.";
        }

        if ("DEPARTMENT_HEAD".equals(role)) {
            return "Reviews department-level assets, employees, requests, allocation and reports.";
        }

        if ("AUDITOR".equals(role)) {
            return "Reviews audit logs, reports, access matrix and compliance-related records.";
        }

        if ("EMPLOYEE".equals(role)) {
            return "Limited self-service access for asset view, requests, returns and QR scanner.";
        }

        return "Custom role configured in the system.";
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

    List<Map<String, String>> roleList = new ArrayList<>();
    List<Map<String, String>> userList = new ArrayList<>();

    int totalRoles = 0;
    int totalUsers = 0;
    int activeUsers = 0;
    int inactiveUsers = 0;

    String loadError = "";

    Connection con = null;
    PreparedStatement rolePs = null;
    PreparedStatement userPs = null;
    ResultSet roleRs = null;
    ResultSet userRs = null;

    try {
        con = DBConnection.getConnection();

        rolePs = con.prepareStatement(
                "SELECT r.role_id, r.role_name, r.description, r.created_at, COUNT(u.user_id) AS user_count "
                + "FROM roles r "
                + "LEFT JOIN users u ON r.role_id = u.role_id "
                + "GROUP BY r.role_id, r.role_name, r.description, r.created_at "
                + "ORDER BY r.role_id ASC"
        );

        roleRs = rolePs.executeQuery();

        while (roleRs.next()) {
            Map<String, String> roleMap = new LinkedHashMap<>();

            roleMap.put("roleId", String.valueOf(roleRs.getInt("role_id")));
            roleMap.put("roleName", roleRs.getString("role_name"));
            roleMap.put("description", roleRs.getString("description"));
            roleMap.put("createdAt", roleRs.getString("created_at"));
            roleMap.put("userCount", String.valueOf(roleRs.getInt("user_count")));

            roleList.add(roleMap);
        }

        totalRoles = roleList.size();

        userPs = con.prepareStatement(
                "SELECT u.user_id, u.username, u.email, u.status, u.created_at, "
                + "r.role_id, r.role_name "
                + "FROM users u "
                + "JOIN roles r ON u.role_id = r.role_id "
                + "WHERE u.username != 'super_admin' "
                + "ORDER BY u.user_id ASC"
        );

        userRs = userPs.executeQuery();

        while (userRs.next()) {
            Map<String, String> userMap = new LinkedHashMap<>();

            String userStatus = userRs.getString("status");

            userMap.put("userId", String.valueOf(userRs.getInt("user_id")));
            userMap.put("username", userRs.getString("username"));
            userMap.put("email", userRs.getString("email"));
            userMap.put("status", userStatus);
            userMap.put("createdAt", userRs.getString("created_at"));
            userMap.put("roleId", String.valueOf(userRs.getInt("role_id")));
            userMap.put("roleName", userRs.getString("role_name"));

            userList.add(userMap);

            if ("ACTIVE".equalsIgnoreCase(userStatus)) {
                activeUsers++;
            } else {
                inactiveUsers++;
            }
        }

        totalUsers = userList.size();

    } catch (Exception e) {
        e.printStackTrace();
        loadError = "Unable to load roles and users. Please check roles/users table.";
    } finally {
        try {
            if (roleRs != null) {
                roleRs.close();
            }

            if (userRs != null) {
                userRs.close();
            }

            if (rolePs != null) {
                rolePs.close();
            }

            if (userPs != null) {
                userPs.close();
            }

            if (con != null) {
                con.close();
            }
        } catch (Exception ex) {
            ex.printStackTrace();
        }
    }

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");
    String updatedUser = request.getParameter("user");
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Manage Roles</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=roles-ui-final-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=roles-ui-final-1">
    <link rel="stylesheet" href="css/manage_roles.css?v=28001">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=roles-ui-final-1">
</head>

<body class="railway-ui">

<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">

        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="asset-hero">
                <h1>Role & User Access Management</h1>

                <p>
                    Manage IR-AMS user access by assigning roles and controlling active/inactive
                    login status for each system user.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-user-shield"></i> Super Admin Control
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-users-gear"></i> Role Assignment
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-toggle-on"></i> User Status
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-clock-rotate-left"></i> Audit Logged
                    </div>
                </div>
            </section>

            <% if ("updated".equals(msg)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    User access updated successfully<%= updatedUser == null ? "." : " for " + safeText(updatedUser) + "." %>
                </div>
            <% } else if ("self".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    You cannot change your own role or status from this page.
                </div>
            <% } else if ("invalid".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Invalid role, user or status selected.
                </div>
            <% } else if ("invalid_fallback".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Invalid fallback role. You cannot reassign the outgoing admin to admin or super_admin.
                </div>
            <% } else if ("server".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Server error occurred while updating user role.
                </div>
            <% } %>

            <% if (!loadError.isEmpty()) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    <%= safeText(loadError) %>
                </div>
            <% } %>

            <section class="role-kpi-grid">

                <div class="role-kpi-card">
                    <i class="fa-solid fa-users-gear"></i>
                    <span>Total Roles</span>
                    <strong><%= totalRoles %></strong>
                </div>

                <div class="role-kpi-card">
                    <i class="fa-solid fa-users"></i>
                    <span>Total Users</span>
                    <strong><%= totalUsers %></strong>
                </div>

                <div class="role-kpi-card">
                    <i class="fa-solid fa-circle-check"></i>
                    <span>Active Users</span>
                    <strong><%= activeUsers %></strong>
                </div>

                <div class="role-kpi-card">
                    <i class="fa-solid fa-circle-xmark"></i>
                    <span>Inactive Users</span>
                    <strong><%= inactiveUsers %></strong>
                </div>

            </section>

            <section class="glass-panel">

                <div class="registry-toolbar">
                    <div>
                        <h2>System Roles</h2>
                        <p class="table-subtext">
                            Fixed role structure used by IR-AMS role-based access control.
                        </p>
                    </div>

                    <div class="registry-actions">
                        <a href="access_matrix.jsp" class="btn">
                            <i class="fa-solid fa-table-cells"></i>
                            Open Access Matrix
                        </a>

                        <a href="ams_copilot.jsp"><i class="fa-solid fa-robot"></i> AI Copilot</a>
              <a href="settings.jsp" class="btn secondary-btn">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Settings
                        </a>
                    </div>
                </div>

                <div class="role-card-grid">

                    <%
                        for (Map<String, String> roleMap : roleList) {
                            String roleName = roleMap.get("roleName");
                            String description = roleMap.get("description");
                            String userCount = roleMap.get("userCount");
                    %>

                    <div class="role-card">
                        <div class="role-card-head">
                            <div class="role-card-icon">
                                <i class="fa-solid <%= roleIcon(roleName) %>"></i>
                            </div>

                            <div>
                                <h3><%= safeText(roleDisplay(roleName)) %></h3>
                                <small><%= safeText(userCount) %> assigned user(s)</small>
                            </div>
                        </div>

                        <p>
                            <%= description == null || description.trim().isEmpty()
                                    ? safeText(rolePurpose(roleName))
                                    : safeText(description) %>
                        </p>
                    </div>

                    <%
                        }
                    %>

                </div>

            </section>

            <br>

            <section class="glass-panel">

                <div class="registry-toolbar">
                    <div>
                        <h2>User Role Assignment</h2>
                        <p class="table-subtext">
                            Change user role and account status. Password is intentionally hidden for security.
                        </p>
                    </div>
                </div>

                <div class="user-table-wrap">
                    <table class="role-user-table" id="roleUserTable">
                        <thead>
                            <tr>
                                <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">User <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Email <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Current Role <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">Created At <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th>Update Access</th>
                            </tr>
                        </thead>

                        <tbody>

                            <%
                                if (userList.isEmpty()) {
                            %>
                                <tr>
                                    <td colspan="6">No users found.</td>
                                </tr>
                            <%
                                }

                                for (Map<String, String> userMap : userList) {
                                    String userId = userMap.get("userId");
                                    String tableUsername = userMap.get("username");
                                    String email = userMap.get("email");
                                    String userStatus = userMap.get("status");
                                    String createdAt = userMap.get("createdAt");
                                    String currentRoleId = userMap.get("roleId");
                                    String currentRoleName = userMap.get("roleName");

                                    boolean isCurrentUser = username.equalsIgnoreCase(tableUsername);
                                    String initials = tableUsername == null || tableUsername.trim().isEmpty()
                                            ? "U"
                                            : tableUsername.trim().substring(0, 1).toUpperCase();
                            %>

                            <tr>
                                <td>
                                    <div class="user-main">
                                        <div class="user-mini-avatar"><%= safeText(initials) %></div>

                                        <div>
                                            <strong><%= safeText(tableUsername) %></strong>
                                            <span>User ID: <%= safeText(userId) %></span>
                                        </div>
                                    </div>
                                </td>

                                <td><%= safeText(email) %></td>

                                <td>
                                    <span class="role-badge">
                                        <i class="fa-solid <%= roleIcon(currentRoleName) %>"></i>
                                        <%= safeText(roleDisplay(currentRoleName)) %>
                                    </span>
                                </td>

                                <td>
                                    <%= statusBadge(userStatus) %>
                                </td>

                                <td><%= safeText(createdAt) %></td>

                                <td>
                                    <% if (isCurrentUser) { %>

                                        <span class="locked-note">
                                            <i class="fa-solid fa-lock"></i>
                                            Current admin locked
                                        </span>

                                    <% } else { %>

                                        <form action="UpdateUserRoleServlet"
                                              method="post"
                                              class="inline-role-form">

                                            <input type="hidden" name="userId" value="<%= safeValue(userId) %>">

                                            <select name="newRole" class="new-role-select" onchange="toggleFallback(this)" required>
                                                <%
                                                    for (Map<String, String> roleMap : roleList) {
                                                        String optionRoleId = roleMap.get("roleId");
                                                        // Fault (fixed): this used to be a raw
                                                        // .toLowerCase() of the roles table's own
                                                        // role_name - correct for five of the six
                                                        // roles, but roles.role_name spells this one
                                                        // "DEPARTMENT_HEAD" while current_role's real
                                                        // enum literal is "dept_head" (missing
                                                        // "artment"). A raw lowercase produced
                                                        // "department_head", a value that matches
                                                        // nothing in the enum - see
                                                        // RoleIdResolver.toEnumRoleValue's own doc for
                                                        // what selecting it would actually have done.
                                                        String optionRoleName = RoleIdResolver.toEnumRoleValue(roleMap.get("roleName"));
                                                        if ("super_admin".equalsIgnoreCase(optionRoleName)) continue;
                                                %>
                                                    <option value="<%= safeValue(optionRoleName) %>"
                                                            <%= optionRoleId.equals(currentRoleId) ? "selected" : "" %>>
                                                        <%= safeText(roleDisplay(roleMap.get("roleName"))) %>
                                                    </option>
                                                <%
                                                    }
                                                %>
                                            </select>
                                            
                                            <select name="outgoingAdminRole" class="fallback-select" style="display: none;">
                                                <option value="employee">Fallback: Employee</option>
                                                <option value="asset_manager">Fallback: Asset Manager</option>
                                                <option value="dept_head">Fallback: Dept Head</option>
                                                <option value="auditor">Fallback: Auditor</option>
                                            </select>

                                            <select name="status" required>
                                                <option value="ACTIVE" <%= "ACTIVE".equalsIgnoreCase(userStatus) ? "selected" : "" %>>
                                                    ACTIVE
                                                </option>

                                                <option value="INACTIVE" <%= "INACTIVE".equalsIgnoreCase(userStatus) ? "selected" : "" %>>
                                                    INACTIVE
                                                </option>
                                            </select>

                                            <button type="submit" class="btn">
                                                <i class="fa-solid fa-floppy-disk"></i>
                                                Update
                                            </button>

                                        </form>

                                    <% } %>
                                </td>
                            </tr>

                            <%
                                }
                            %>

                        </tbody>
                    </table>
                </div>

            </section>

            <br>

            <section class="glass-panel">

                <div class="registry-toolbar">
                    <div>
                        <h2>Security Notes</h2>
                        <p class="table-subtext">
                            Administrative safety rules followed by this page.
                        </p>
                    </div>
                </div>

                <div class="policy-grid">

                    <div class="policy-card">
                        <h3>
                            <i class="fa-solid fa-lock"></i>
                            Current Admin Protection
                        </h3>

                        <p>
                            The logged-in Super Admin cannot change their own role or inactive status from this page,
                            preventing accidental lockout.
                        </p>
                    </div>

                    <div class="policy-card">
                        <h3>
                            <i class="fa-solid fa-key"></i>
                            Password Hidden
                        </h3>

                        <p>
                            Password values are never displayed on the role management page for security and project compliance.
                        </p>
                    </div>

                    <div class="policy-card">
                        <h3>
                            <i class="fa-solid fa-clock-rotate-left"></i>
                            Audit Tracking
                        </h3>

                        <p>
                            Every role or status update is recorded in audit logs with target user, old role and new role information.
                        </p>
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
<script>
    var sortDirections = [true, true, true, true, true];
    
    function toggleFallback(selectElement) {
        var form = selectElement.closest('form');
        var fallbackSelect = form.querySelector('.fallback-select');
        if (selectElement.value === 'admin') {
            fallbackSelect.style.display = 'inline-block';
        } else {
            fallbackSelect.style.display = 'none';
            fallbackSelect.value = 'employee';
        }
    }
    
    function sortTable(columnIndex) {
        var table = document.getElementById("roleUserTable");
        var tbody = table.querySelector("tbody");
        var rows = Array.from(tbody.querySelectorAll("tr"));
        
        if (rows.length === 0) return;
        if (rows.length === 1 && rows[0].querySelector("td[colspan]")) return;

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