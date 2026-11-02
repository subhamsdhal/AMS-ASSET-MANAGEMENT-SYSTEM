﻿<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.NumberFormat"%>
<%@page import="com.mycompany.asset_management_system_ams.RoleAssignmentDAO"%>

<%!
    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }
        return value.trim()
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

    private String shortText(String value, int max) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim();
        return text.length() <= max ? text : text.substring(0, max) + "...";
    }

    private String indianNumber(long value) {
        try {
            NumberFormat nf = NumberFormat.getNumberInstance(new Locale("en", "IN"));
            nf.setMaximumFractionDigits(0);
            return nf.format(value);
        } catch (Exception e) {
            return String.valueOf(value);
        }
    }

    private Map<String, String> singleRow(String sql, String id) {
        Map<String, String> row = new HashMap<>();

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int columnCount = meta.getColumnCount();

                if (rs.next()) {
                    for (int i = 1; i <= columnCount; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return row;
    }

    private List<Map<String, String>> listRows(String sql, String id) {
        List<Map<String, String>> rows = new ArrayList<>();

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int columnCount = meta.getColumnCount();

                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();

                    for (int i = 1; i <= columnCount; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }

                    rows.add(row);
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return rows;
    }

    private int singleInt(String sql, String id) {
        int count = 0;

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    count = rs.getInt(1);
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return count;
    }

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) {
            return "";
        }

        String value = row.get(key);
        return value == null ? "" : value;
    }

    private String initials(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "IR";
        }

        String[] parts = value.trim().split("\\s+");
        StringBuilder out = new StringBuilder();

        for (String part : parts) {
            if (part.length() > 0 && out.length() < 2) {
                out.append(Character.toUpperCase(part.charAt(0)));
            }
        }

        if (out.length() == 0) {
            return "IR";
        }

        return out.toString();
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

    String employeeId = request.getParameter("id");

    if (employeeId == null || employeeId.trim().isEmpty()) {
        employeeId = request.getParameter("employee_id");
    }

    if (employeeId == null || employeeId.trim().isEmpty()) {
        response.sendRedirect("employees.jsp?error=invalid");
        return;
    }

    employeeId = employeeId.trim();

    boolean isDepartmentHead = "DEPARTMENT_HEAD".equalsIgnoreCase(role);
    boolean canManageEmployees = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role) || isDepartmentHead;
    
    int loggedInUserId = 1;
    if (session.getAttribute("user_id") != null) {
        loggedInUserId = Integer.parseInt(session.getAttribute("user_id").toString());
    } else if (session.getAttribute("userId") != null) {
        loggedInUserId = Integer.parseInt(session.getAttribute("userId").toString());
    }

    if (isDepartmentHead) {
        com.mycompany.asset_management_system_ams.EmployeeDAO dao = new com.mycompany.asset_management_system_ams.EmployeeDAO();
        if (!dao.isEmployeeUnderDepartmentHead(Integer.parseInt(employeeId), loggedInUserId)) {
            response.sendRedirect("employees.jsp?access=denied");
            return;
        }
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> employee = singleRow(
            "SELECT "
            + "e.employee_id, "
            + "e.employee_code, "
            + "e.employee_name AS full_name, "
            + "e.designation, "
            + "e.email, "
            + "e.phone, "
            + "DATE_FORMAT(e.joining_date, '%d %b %Y') AS joining_date, "
            + "e.employee_status, "
            + "e.profile_image_path, "
            + "DATE_FORMAT(e.created_at, '%d %b %Y, %h:%i %p') AS created_at, "
            + "DATE_FORMAT(e.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, "
            + "COALESCE(d.department_name, 'No Department') AS department_name, "
            + "COALESCE(rd.division_name, '') AS division_name, "
            + "COALESCE(rl.location_code, '') AS location_code, "
            + "COALESCE(rl.location_name, '') AS location_name, "
            + "COALESCE(rl.location_type, '') AS location_type, "
            + "COALESCE(rl.building_block, '') AS building_block, "
            + "COALESCE(rl.floor_level, '') AS floor_level, "
            + "COALESCE(rl.room_no, '') AS room_no, "
            + "COALESCE(u.username, '') AS login_username, "
            + "COALESCE(u.status, '') AS login_status "
            + "FROM employees e "
            + "LEFT JOIN departments d ON e.department_id = d.department_id "
            + "LEFT JOIN railway_divisions rd ON e.division_id = rd.division_id "
            + "LEFT JOIN railway_locations rl ON e.location_id = rl.location_id "
            + "LEFT JOIN users u ON e.user_id = u.user_id "
            + "WHERE e.employee_id = ? "
            + "LIMIT 1",
            employeeId
    );

    if (employee.isEmpty()) {
        response.sendRedirect("employees.jsp?error=notfound");
        return;
    }

    int totalAllocations = singleInt("SELECT COUNT(*) FROM asset_allocation WHERE employee_id = ?", employeeId);
    int activeAllocations = singleInt("SELECT COUNT(*) FROM asset_allocation WHERE employee_id = ? AND allocation_status <> 'RETURNED'", employeeId);
    int totalReturns = singleInt("SELECT COUNT(*) FROM asset_returns WHERE employee_id = ?", employeeId);
    int totalRequests = singleInt("SELECT COUNT(*) FROM asset_requests WHERE employee_id = ?", employeeId);
    int pendingRequests = singleInt("SELECT COUNT(*) FROM asset_requests WHERE employee_id = ? AND request_status = 'PENDING'", employeeId);
    int verificationDuties = singleInt("SELECT COUNT(*) FROM physical_verification WHERE verified_by_employee_id = ?", employeeId);

    List<Map<String, String>> assetRows = listRows(
            "SELECT "
            + "aa.allocation_id, "
            + "aa.asset_id, "
            + "aa.allocation_status, "
            + "DATE_FORMAT(aa.allocation_date, '%d %b %Y') AS allocation_date, "
            + "DATE_FORMAT(ar_t.return_date, '%d %b %Y') AS return_date, "
            + "a.asset_code, "
            + "a.asset_name, "
            + "a.asset_status, "
            + "a.service_status, "
            + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
            + "COALESCE(v.vendor_name, 'Unknown') AS supplier_name, "
            + "COALESCE(ar_t.return_condition, '') AS return_condition "
            + "FROM asset_allocation aa "
            + "LEFT JOIN assets a ON aa.asset_id = a.asset_id "
            + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
            + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
            + "LEFT JOIN asset_returns ar_t ON aa.allocation_id = ar_t.allocation_id "
            + "WHERE aa.employee_id = ? "
            + "ORDER BY aa.allocation_date DESC, aa.allocation_id DESC",
            employeeId
    );

    List<Map<String, String>> requestRows = listRows(
            "SELECT "
            + "ar.request_id, "
            + "ar.request_type, "
            + "ar.request_status, "
            + "ar.priority, "
            + "DATE_FORMAT(ar.request_date, '%d %b %Y') AS request_date, "
            + "DATE_FORMAT(ar.required_by_date, '%d %b %Y') AS required_by_date, "
            + "COALESCE(ac.category_name, 'No Category') AS category_name, "
            + "COALESCE(ar.request_reason, '') AS request_reason, "
            + "COALESCE(ar.remarks, '') AS remarks "
            + "FROM asset_requests ar "
            + "LEFT JOIN asset_categories ac ON ar.category_id = ac.category_id "
            + "WHERE ar.employee_id = ? "
            + "ORDER BY ar.request_id DESC "
            + "LIMIT 10",
            employeeId
    );

    List<Map<String, String>> verificationRows = listRows(
            "SELECT "
            + "pv.verification_id, "
            + "pv.asset_id, "
            + "a.asset_code, "
            + "a.asset_name, "
            + "DATE_FORMAT(pv.verification_date, '%d %b %Y') AS verification_date, "
            + "pv.asset_found, "
            + "pv.verification_status, "
            + "pv.physical_condition, "
            + "COALESCE(pv.remarks, '') AS remarks "
            + "FROM physical_verification pv "
            + "LEFT JOIN assets a ON pv.asset_id = a.asset_id "
            + "WHERE pv.verified_by_employee_id = ? "
            + "ORDER BY pv.verification_id DESC "
            + "LIMIT 10",
            employeeId
    );

    String employeeName = rowValue(employee, "full_name");
    String employeeStatus = rowValue(employee, "employee_status");

    String statusClass = "";
    String upperStatus = employeeStatus == null ? "" : employeeStatus.toUpperCase(Locale.ENGLISH);

    if (upperStatus.contains("INACTIVE") || upperStatus.contains("SUSPENDED")) {
        statusClass = "danger";
    }

    boolean canUploadImage = false;
    try {
        Integer sessionUserId = (Integer) session.getAttribute("user_id");
        if (sessionUserId != null) {
            com.mycompany.asset_management_system_ams.EmployeeDAO tempDao = new com.mycompany.asset_management_system_ams.EmployeeDAO();
            if ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) {
                canUploadImage = true;
            } else if ("DEPARTMENT_HEAD".equals(role)) {
                canUploadImage = tempDao.isEmployeeUnderDepartmentHead(Integer.parseInt(employeeId), sessionUserId);
            } else if ("EMPLOYEE".equals(role)) {
                int loggedInEmployeeId = tempDao.getEmployeeIdByUserId(sessionUserId);
                canUploadImage = (loggedInEmployeeId == Integer.parseInt(employeeId));
            }
        }
    } catch (Exception e) {
        // ignore
    }

    List<Map<String, String>> documentRows = listRows(
            "SELECT "
            + "d.document_id, "
            + "d.document_title, "
            + "d.document_type, "
            + "d.original_file_name, "
            + "d.file_size, "
            + "DATE_FORMAT(d.uploaded_at, '%d %b %Y, %h:%i %p') AS uploaded_at, "
            + "COALESCE(u.username, 'Unknown') AS uploaded_by_name "
            + "FROM employee_documents d "
            + "LEFT JOIN users u ON d.uploaded_by = u.user_id "
            + "WHERE d.employee_id = ? AND d.status = 'ACTIVE' "
            + "ORDER BY d.uploaded_at DESC",
            employeeId
    );
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Holder Profile - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/view_employee.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp">
        <jsp:param name="activePage" value="employees" />
    </jsp:include>

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content detail-board">

            <%
                String error = request.getParameter("error");
                String msg = request.getParameter("msg");
                
                if (error != null && !error.isEmpty()) {
            %>
                <div class="page-error" style="margin-bottom: 20px; padding: 15px; background: #ffebee; color: #c62828; border-radius: 8px;">
                    <i class="fa-solid fa-circle-exclamation"></i>
                    <%
                        if ("document_denied".equals(error)) out.print("Permission denied to manage documents.");
                        else if ("missing_fields".equals(error)) out.print("Required document fields are missing.");
                        else if ("doc_upload_failed".equals(error)) out.print("Failed to upload document. Please check file size and type.");
                        else if ("document_missing".equals(error)) out.print("Document file is missing or unreadable.");
                        else if ("delete_denied".equals(error)) out.print("Permission denied to delete document.");
                        else if ("delete_failed".equals(error)) out.print("Failed to delete document.");
                        else if ("invalid_document".equals(error)) out.print("Invalid document specified.");
                        else if ("document_delete".equals(error)) out.print("Failed to delete document.");
                        else if ("nottransferable".equals(error)) out.print("Only active employees can be transferred.");
                        else if ("notretirable".equals(error)) out.print("Only active employees can be retired.");
                        else out.print("An error occurred.");
                    %>
                </div>
            <%
                } else if (msg != null && !msg.isEmpty()) {
            %>
                <div class="page-success" style="margin-bottom: 20px; padding: 15px; background: #eaf7ef; color: #04733b; border-radius: 8px;">
                    <i class="fa-solid fa-circle-check"></i>
                    <%
                        if ("profile_updated".equals(msg)) out.print("Employee profile updated successfully.");
                        else if ("status_updated".equals(msg)) out.print("Employee status updated successfully.");
                        else if ("doc_uploaded".equals(msg)) out.print("Document uploaded successfully.");
                        else if ("document_deleted".equals(msg)) out.print("Document deleted successfully.");
                        else if ("transferred".equals(msg)) out.print("Employee transferred successfully. Retained/returned assets have been updated.");
                        else if ("retired".equals(msg)) out.print("Employee retired successfully. All allocated assets have been returned.");
                        else out.print("Operation completed successfully.");
                    %>
                </div>
            <%
                }
            %>

            <section class="detail-hero" style="display: flex; gap: 20px; align-items: center; position: relative;">
                <div class="employee-avatar" style="width: 80px; height: 80px; font-size: 32px; border-radius: 50%; overflow: hidden; display: flex; align-items: center; justify-content: center; background-color: var(--ir-blue); color: #fff; flex-shrink: 0;">
                    <% if (rowValue(employee, "profile_image_path") != null && !rowValue(employee, "profile_image_path").trim().isEmpty()) { %>
                        <img src="<%= safeText(request.getContextPath() + "/" + rowValue(employee, "profile_image_path")) %>" class="employee-avatar-img" alt="Profile" style="width: 100%; height: 100%; object-fit: cover;">
                    <% } else { %>
                        <%= safeText(initials(employeeName)) %>
                    <% } %>
                </div>

                <div style="flex: 1;">
                    <div style="display: flex; align-items: center; gap: 10px;">
                        <h1 style="margin-bottom: 0;"><%= safeText(employeeName) %></h1>
                        <% if (canUploadImage) { %>
                            <button type="button" class="btn btn-secondary btn-sm" onclick="document.getElementById('profileImageUploadForm').style.display = document.getElementById('profileImageUploadForm').style.display === 'none' ? 'block' : 'none'" style="padding: 4px 8px; font-size: 12px; margin-top: 5px;">
                                <i class="fa-solid fa-camera"></i>
                            </button>
                        <% } %>
                    </div>
                    <p style="margin-top: 5px;">
                        <strong><%= safeText(rowValue(employee, "employee_code")) %></strong>
                        · <%= safeText(rowValue(employee, "designation")) %>
                        · <%= safeText(rowValue(employee, "department_name")) %>
                        · <%= safeText(rowValue(employee, "location_name")) %>
                    </p>
                </div>

                <div class="hero-actions">
                    <span class="status-pill <%= statusClass %>">
                        <i class="fa-solid fa-circle-check"></i>
                        <%= safeText(cleanLabel(employeeStatus)) %>
                    </span>

                    <% if (canManageEmployees) { 
                        if (rowValue(employee, "login_username").isEmpty()) { %>
                        <button class="btn btn-secondary" onclick="generateLogin('<%= safeText(employeeId) %>')">
                            <i class="fa-solid fa-key"></i> Generate Login
                        </button>
                        <% } else { %>
                        <button class="btn btn-secondary" onclick="resetPassword('<%= safeText(employeeId) %>')">
                            <i class="fa-solid fa-unlock-keyhole"></i> Reset Password
                        </button>
                        <% } %>
                        <a href="edit_employee.jsp?id=<%= safeText(employeeId) %>" class="btn btn-primary">
                            <i class="fa-solid fa-pen"></i>
                            Edit
                        </a>

                        <% if ("ACTIVE".equalsIgnoreCase(employeeStatus)) { %>
                            <a href="transfer_employee.jsp?id=<%= safeText(employeeId) %>" class="btn btn-secondary" title="Transfer to a new department">
                                <i class="fa-solid fa-right-left"></i>
                                Transfer
                            </a>

                            <a href="retire_employee.jsp?id=<%= safeText(employeeId) %>" class="btn btn-secondary" title="Mark as retired">
                                <i class="fa-solid fa-user-clock"></i>
                                Retire
                            </a>
                        <% } %>
                    <% } %>

                    <a href="employees.jsp" class="btn btn-secondary">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back
                    </a>
                </div>
            </section>

            <% if (canUploadImage) { %>
            <div id="profileImageUploadForm" style="display: none; background: rgba(0,0,0,0.03); padding: 20px; border-radius: 8px; margin-bottom: 20px; border: 1px solid rgba(0,0,0,0.1);">
                <h3 style="margin-bottom: 15px; font-size: 16px;">Update Profile Image</h3>
                <form action="UploadEmployeeProfileImageServlet" method="post" enctype="multipart/form-data">
                    <input type="hidden" name="employeeId" value="<%= safeText(employeeId) %>">
                    
                    <div class="form-group" style="margin-bottom: 15px;">
                        <label class="form-label">Select Image File <span class="required" style="color:red;">*</span></label>
                        <input type="file" name="profileImage" class="form-control" required accept=".jpg,.jpeg,.png,.webp" style="padding: 10px; border: 1px solid #ccc; border-radius: 4px; width: 100%; background: #fff;">
                        <small style="display:block; margin-top:5px; color:var(--text-secondary);">Allowed: JPG, PNG, WEBP. Max: 5 MB.</small>
                    </div>

                    <div class="form-actions" style="margin-top: 15px; text-align: right;">
                        <button type="button" class="btn btn-secondary" onclick="document.getElementById('profileImageUploadForm').style.display='none'">Cancel</button>
                        <button type="submit" class="btn btn-primary"><i class="fa-solid fa-upload"></i> Upload</button>
                    </div>
                </form>
            </div>
            <% } %>

            <section class="summary-grid">
                <div class="summary-card">
                    <span>Active Allocations</span>
                    <strong><%= indianNumber(activeAllocations) %></strong>
                </div>

                <div class="summary-card">
                    <span>Total Allocation History</span>
                    <strong><%= indianNumber(totalAllocations) %></strong>
                </div>

                <div class="summary-card">
                    <span>Asset Requests</span>
                    <strong><%= indianNumber(totalRequests) %></strong>
                </div>

                <div class="summary-card">
                    <span>Pending Requests</span>
                    <strong><%= indianNumber(pendingRequests) %></strong>
                </div>

                <div class="summary-card">
                    <span>Returns</span>
                    <strong><%= indianNumber(totalReturns) %></strong>
                </div>

                <div class="summary-card">
                    <span>Verification Duties</span>
                    <strong><%= indianNumber(verificationDuties) %></strong>
                </div>

                <div class="summary-card">
                    <span>Department</span>
                    <strong><%= safeText(rowValue(employee, "department_name")) %></strong>
                </div>

                <div class="summary-card">
                    <span>Division</span>
                    <strong><%= safeText(rowValue(employee, "division_name")) %></strong>
                </div>
            </section>

            <section class="employee-profile-summary-grid">
                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Holder Profile</h2>
                    </div>

                    <table class="detail-table">
                        <tr><th>Employee Code</th><td><%= safeText(rowValue(employee, "employee_code")) %></td></tr>
                        <tr><th>Full Name</th><td><%= safeText(employeeName) %></td></tr>
                        <tr><th>Designation</th><td><%= safeText(rowValue(employee, "designation")) %></td></tr>
                        <tr>
                            <th>System Role(s)</th>
                            <td>
                                <%
                                    Map<Integer, String> summaryMap = RoleAssignmentDAO.getActiveDutySummaryForEmployees();
                                    String roleSummary = summaryMap.getOrDefault(Integer.parseInt(employeeId), "Employee");
                                %>
                                <%= safeText(roleSummary) %>
                            </td>
                        </tr>
                        <tr><th>Email</th><td><%= safeText(rowValue(employee, "email")) %></td></tr>
                        <tr><th>Phone</th><td><%= safeText(rowValue(employee, "phone")) %></td></tr>
                        <tr><th>Department</th><td><%= safeText(rowValue(employee, "department_name")) %></td></tr>
                        <tr><th>Division</th><td><%= safeText(rowValue(employee, "division_name")) %></td></tr>
                        <tr><th>Location</th><td><%= safeText(rowValue(employee, "location_name")) %></td></tr>
                        <tr><th>Room / Floor</th><td><%= safeText(rowValue(employee, "building_block")) %> · <%= safeText(rowValue(employee, "floor_level")) %> · Room <%= safeText(rowValue(employee, "room_no")) %></td></tr>
                        <tr><th>Joining Date</th><td><%= safeText(rowValue(employee, "joining_date")) %></td></tr>
                        <tr><th>Employee Status</th><td><%= safeText(cleanLabel(employeeStatus)) %></td></tr>
                        <tr><th>Login Username</th><td><%= safeText(rowValue(employee, "login_username")) %></td></tr>
                        <tr><th>Login Status</th><td><%= safeText(cleanLabel(rowValue(employee, "login_status"))) %></td></tr>
                        <tr><th>Created On</th><td><%= safeText(rowValue(employee, "created_at")) %></td></tr>
                        <tr><th>Updated On</th><td><%= safeText(rowValue(employee, "updated_at")) %></td></tr>
                    </table>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Asset Requests</h2>
                    </div>

                    <div class="timeline-list">
                        <% if (requestRows.isEmpty()) { %>
                            <div class="empty-box">
                                <i class="fa-regular fa-square-plus"></i>
                                <strong>No request history</strong>
                                <span>Asset planning and request records will appear here.</span>
                            </div>
                        <% } else {
                            for (Map<String, String> row : requestRows) {
                        %>
                            <a class="timeline-row" href="view_request.jsp?id=<%= safeText(rowValue(row, "request_id")) %>">
                                <div class="timeline-icon"><i class="fa-regular fa-square-plus"></i></div>
                                <div class="timeline-text">
                                    <strong>Request #<%= safeText(rowValue(row, "request_id")) %> · <%= safeText(cleanLabel(rowValue(row, "request_status"))) %></strong>
                                    <span><%= safeText(cleanLabel(rowValue(row, "request_type"))) %> · <%= safeText(rowValue(row, "category_name")) %> · <%= safeText(shortText(rowValue(row, "request_reason"), 80)) %></span>
                                </div>
                                <div class="timeline-date"><%= safeText(rowValue(row, "request_date")) %></div>
                            </a>
                        <%  }
                        } %>
                    </div>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Verification Duties</h2>
                    </div>

                    <div class="timeline-list">
                        <% if (verificationRows.isEmpty()) { %>
                            <div class="empty-box">
                                <i class="fa-solid fa-shield-halved"></i>
                                <strong>No verification duties found</strong>
                                <span>Physical verification work assigned to this employee will appear here.</span>
                            </div>
                        <% } else {
                            for (Map<String, String> row : verificationRows) {
                        %>
                            <a class="timeline-row" href="view_asset.jsp?id=<%= safeText(rowValue(row, "asset_id")) %>">
                                <div class="timeline-icon"><i class="fa-solid fa-shield-halved"></i></div>
                                <div class="timeline-text">
                                    <strong><%= safeText(rowValue(row, "asset_code")) %> · <%= safeText(rowValue(row, "asset_name")) %></strong>
                                    <span><%= safeText(cleanLabel(rowValue(row, "verification_status"))) %> · Found: <%= safeText(cleanLabel(rowValue(row, "asset_found"))) %> · <%= safeText(cleanLabel(rowValue(row, "physical_condition"))) %></span>
                                </div>
                                <div class="timeline-date"><%= safeText(rowValue(row, "verification_date")) %></div>
                            </a>
                        <%  }
                        } %>
                    </div>
                </div>
            </section>

            <section class="employee-document-vault-section" style="margin-top: 20px;">
                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Employee Document Vault</h2>
                        <% if (canManageEmployees) { %>
                            <button type="button" class="btn btn-secondary" onclick="document.getElementById('inlineUploadForm').style.display = document.getElementById('inlineUploadForm').style.display === 'none' ? 'block' : 'none'">
                                <i class="fa-solid fa-cloud-arrow-up"></i> Upload Document
                            </button>
                        <% } %>
                    </div>

                    <% if (canManageEmployees) { %>
                    <div id="inlineUploadForm" style="display: none; background: rgba(0,0,0,0.03); padding: 20px; border-radius: 8px; margin-bottom: 20px; border: 1px solid rgba(0,0,0,0.1);">
                        <h3 style="margin-bottom: 15px; font-size: 16px;">Upload New Document</h3>
                        <form action="UploadEmployeeDocumentServlet" method="post" enctype="multipart/form-data">
                            <input type="hidden" name="employeeId" value="<%= safeText(employeeId) %>">
                            
                            <div class="form-group" style="margin-bottom: 15px;">
                                <label class="form-label">Document Title <span class="required" style="color:red;">*</span></label>
                                <input type="text" name="documentTitle" class="form-control" required placeholder="e.g. Aadhar Card, Joining Letter" style="width: 100%;">
                            </div>

                            <div class="form-group" style="margin-bottom: 15px;">
                                <label class="form-label">Document Type <span class="required" style="color:red;">*</span></label>
                                <select name="documentType" class="form-control" required style="width: 100%;">
                                    <option value="">Select Type</option>
                                    <option value="ID_PROOF">ID Proof</option>
                                    <option value="JOINING_LETTER">Joining Letter</option>
                                    <option value="APPOINTMENT_LETTER">Appointment Letter</option>
                                    <option value="CERTIFICATE">Certificate</option>
                                    <option value="SERVICE_DOCUMENT">Service Document</option>
                                    <option value="OTHER">Other</option>
                                </select>
                            </div>

                            <div class="form-group" style="margin-bottom: 15px;">
                                <label class="form-label">Select File <span class="required" style="color:red;">*</span></label>
                                <input type="file" name="employeeDocument" class="form-control" required accept=".pdf,.jpg,.jpeg,.png,.doc,.docx" style="padding: 10px; border: 1px solid #ccc; border-radius: 4px; width: 100%; background: #fff;">
                                <small style="display:block; margin-top:5px; color:var(--text-secondary);">Allowed: PDF, JPG, PNG, DOC, DOCX. Max: 5 MB.</small>
                            </div>

                            <div class="form-actions" style="margin-top: 15px; text-align: right;">
                                <button type="button" class="btn btn-secondary" onclick="document.getElementById('inlineUploadForm').style.display='none'">Cancel</button>
                                <button type="submit" class="btn btn-primary"><i class="fa-solid fa-upload"></i> Upload</button>
                            </div>
                        </form>
                    </div>
                    <% } %>

                    <div class="table-responsive employee-document-vault-wrapper">
                        <table class="data-table employee-document-vault-table">
                            <thead>
                                <tr>
                                    <th class="doc-title-col">Document Title</th>
                                    <th class="nowrap-col">Type</th>
                                    <th class="doc-title-col">File Name</th>
                                    <th class="nowrap-col">Size</th>
                                    <th class="nowrap-col">Uploaded By</th>
                                    <th class="nowrap-col">Uploaded At</th>
                                    <th class="nowrap-col">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                <% if (documentRows.isEmpty()) { %>
                                    <tr>
                                        <td colspan="7" style="text-align: center; color: var(--text-secondary); padding: 30px;">
                                            <i class="fa-solid fa-folder-open" style="font-size: 24px; display: block; margin-bottom: 10px;"></i>
                                            No documents uploaded for this employee.
                                        </td>
                                    </tr>
                                <% } else {
                                    for (Map<String, String> row : documentRows) {
                                        long sizeBytes = Long.parseLong(rowValue(row, "file_size").isEmpty() ? "0" : rowValue(row, "file_size"));
                                        String sizeText = (sizeBytes / 1024) + " KB";
                                %>
                                    <tr>
                                        <td class="wrap-col"><strong><%= safeText(rowValue(row, "document_title")) %></strong></td>
                                        <td class="nowrap-col"><span class="status-pill"><%= safeText(cleanLabel(rowValue(row, "document_type"))) %></span></td>
                                        <td class="wrap-col"><%= safeText(rowValue(row, "original_file_name")) %></td>
                                        <td class="nowrap-col"><%= sizeText %></td>
                                        <td class="nowrap-col"><%= safeText(rowValue(row, "uploaded_by_name")) %></td>
                                        <td class="nowrap-col"><%= safeText(rowValue(row, "uploaded_at")) %></td>
                                        <td class="action-cell nowrap-col">
                                            <a href="DownloadEmployeeDocumentServlet?id=<%= safeText(rowValue(row, "document_id")) %>" target="_blank" class="action-icon view" title="View / Download">
                                                <i class="fa-solid fa-download"></i>
                                            </a>
                                            <% if (canManageEmployees) { %>
                                            <form action="DeleteEmployeeDocumentServlet" method="post" style="display:inline;" onsubmit="return confirm('Are you sure you want to delete this document?');">
                                                <input type="hidden" name="id" value="<%= safeText(rowValue(row, "document_id")) %>">
                                                <input type="hidden" name="employeeId" value="<%= safeText(employeeId) %>">
                                                <button type="submit" class="action-icon delete" style="border:none; background:none; cursor:pointer;" title="Delete Document">
                                                    <i class="fa-solid fa-trash-can"></i>
                                                </button>
                                            </form>
                                            <% } %>
                                        </td>
                                    </tr>
                                <%  }
                                } %>
                            </tbody>
                        </table>
                    </div>
                </div>
            </section>

            <section class="detail-grid" style="grid-template-columns: 1fr; margin-top: 20px;">
                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Employee Asset History</h2>
                    </div>

                    <div class="table-responsive employee-asset-history-wrapper">
                        <table class="data-table employee-asset-history-table">
                            <thead>
                                <tr>
                                    <th class="nowrap-col">Asset Code</th>
                                    <th class="asset-name-col">Asset Name</th>
                                    <th class="wrap-col">Category</th>
                                    <th class="wrap-col">Supplier</th>
                                    <th class="nowrap-col">Allocation Date</th>
                                    <th class="nowrap-col">Return Date</th>
                                    <th class="wrap-col">Return Condition</th>
                                    <th class="nowrap-col">Allocation Status</th>
                                    <th class="nowrap-col">Current Status</th>
                                </tr>
                            </thead>
                            <tbody>
                                <% if (assetRows.isEmpty()) { %>
                                    <tr>
                                        <td colspan="9" style="text-align: center; color: var(--text-secondary); padding: 30px;">
                                            <i class="fa-solid fa-cubes" style="font-size: 24px; display: block; margin-bottom: 10px;"></i>
                                            No asset allocation history found for this employee.
                                        </td>
                                    </tr>
                                <% } else {
                                    for (Map<String, String> row : assetRows) {
                                        String allocStatus = rowValue(row, "allocation_status");
                                        String retDate = rowValue(row, "return_date");
                                        boolean isReturned = "RETURNED".equalsIgnoreCase(allocStatus) || !retDate.isEmpty();
                                %>
                                    <tr>
                                        <td class="nowrap-col"><strong><a href="view_asset.jsp?id=<%= safeText(rowValue(row, "asset_id")) %>" style="color:var(--ir-blue); text-decoration:none;"><%= safeText(rowValue(row, "asset_code")) %></a></strong></td>
                                        <td class="asset-name-col"><%= safeText(rowValue(row, "asset_name")) %></td>
                                        <td class="wrap-col"><%= safeText(rowValue(row, "category_name")) %></td>
                                        <td class="wrap-col"><%= safeText(rowValue(row, "supplier_name")) %></td>
                                        <td class="nowrap-col"><%= safeText(rowValue(row, "allocation_date")) %></td>
                                        <td class="nowrap-col"><%= isReturned ? safeText(retDate) : "-" %></td>
                                        <td class="wrap-col"><%= isReturned ? safeText(cleanLabel(rowValue(row, "return_condition"))) : "-" %></td>
                                        <td class="nowrap-col">
                                            <% if (isReturned) { %>
                                                <span class="status-pill neutral">Returned</span>
                                            <% } else { %>
                                                <span class="status-pill success">Currently Allocated</span>
                                            <% } %>
                                        </td>
                                        <td class="nowrap-col">
                                            <span class="status-pill"><%= safeText(cleanLabel(rowValue(row, "asset_status"))) %></span>
                                        </td>
                                    </tr>
                                <%  }
                                } %>
                            </tbody>
                        </table>
                    </div>
                </div>
            </section>
        </div>
    </main>
</div>



<script src="js/topbar-search.js?v=employee-maintenance-inner-1"></script>
<script src="js/user-dropdown.js?v=employee-maintenance-inner-1"></script>
<script src="js/sidebar-role.js?v=employee-maintenance-inner-1"></script>

<script>
    const contextPath = '<%= request.getContextPath() %>';

    function generateLogin(employeeId) {
        if (!confirm('Are you sure you want to generate a login account for this employee?')) return;

        fetch(contextPath + '/GenerateEmployeeLoginServlet', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
                'Accept': 'application/json'
            },
            body: new URLSearchParams({
                action: 'generate',
                employeeId: employeeId
            })
        })
        .then(async response => {
            if (!response.ok) throw new Error(await response.text());
            return response.json();
        })
        .then(data => {
            if (data.status === 'ok') {
                alert('Login account generated successfully!\n\nUsername: ' + data.username + '\nTemporary Password: ' + data.tempPassword + '\n\nPlease copy the temporary password now. It will not be shown again.');
                window.location.reload();
            } else {
                alert('Failed: ' + data.error);
            }
        })
        .catch(error => {
            console.error(error);
            alert('Error generating login.');
        });
    }

    function resetPassword(employeeId) {
        if (!confirm('Are you sure you want to reset the password for this employee?')) return;

        fetch(contextPath + '/GenerateEmployeeLoginServlet', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
                'Accept': 'application/json'
            },
            body: new URLSearchParams({
                action: 'reset',
                employeeId: employeeId
            })
        })
        .then(async response => {
            if (!response.ok) throw new Error(await response.text());
            return response.json();
        })
        .then(data => {
            if (data.status === 'ok') {
                alert('Password reset successfully!\n\nTemporary Password: ' + data.tempPassword + '\n\nPlease copy the temporary password now. It will not be shown again.');
                window.location.reload();
            } else {
                alert('Failed: ' + data.error);
            }
        })
        .catch(error => {
            console.error(error);
            alert('Error resetting password.');
        });
    }
</script>

<script src="js/ir-body-watermark.js?v=employee-maintenance-inner-1"></script>
<script src="js/dashboard-actions.js?v=employee-maintenance-inner-1"></script>

</body>
</html>
