<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.sql.*"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");
    Object userIdObj = session.getAttribute("user_id");
    Object employeeIdObj = session.getAttribute("employee_id");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null || userIdObj == null || employeeIdObj == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    String error = request.getParameter("error");
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>New Asset Request - IR-AMS</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
    <style>
        .hero-banner {
            background: linear-gradient(135deg, #f0f7ff, #e0f2fe);
            padding: 24px 30px;
            border-radius: 12px;
            margin-bottom: 24px;
            border: 1px solid #bae6fd;
            display: flex;
            align-items: center;
            justify-content: space-between;
            box-shadow: 0 2px 4px rgba(0,0,0,0.02);
        }
        .hero-banner h1 { margin: 0; color: #0f172a; font-size: 24px; font-weight: 700; }
        .hero-banner p { margin: 8px 0 0 0; color: #475569; font-size: 15px; }
        
        .panel {
            background: #ffffff;
            border: 1px solid #e2e8f0;
            border-radius: 12px;
            padding: 24px;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);
            max-width: 600px;
        }
        .panel-header { margin-bottom: 20px; }
        .panel-header h2 { margin: 0; font-size: 18px; color: #0f172a; font-weight: 700; }

        .form-group { margin-bottom: 16px; }
        .form-group label { display: block; color: #475569; font-weight: 600; margin-bottom: 6px; font-size: 14px; }
        .form-group select, .form-group input {
            width: 100%;
            padding: 10px 14px;
            border: 1px solid #cbd5e1;
            border-radius: 8px;
            background: #f8fafc;
            color: #0f172a;
            font-size: 14px;
            transition: 0.2s ease;
        }
        .form-group select:focus, .form-group input:focus {
            border-color: #0284c7;
            background: #ffffff;
            outline: none;
            box-shadow: 0 0 0 3px rgba(2, 132, 199, 0.1);
        }
        
        .btn-submit {
            background: #0284c7;
            color: #fff;
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            font-weight: 600;
            cursor: pointer;
            width: 100%;
            transition: 0.2s ease;
            font-size: 15px;
            box-shadow: 0 4px 6px rgba(2, 132, 199, 0.2);
        }
        .btn-submit:hover { background: #0369a1; transform: translateY(-1px); }

        .alert-error {
            background: #fef2f2;
            color: #b91c1c;
            padding: 12px 16px;
            border: 1px solid #fecaca;
            border-radius: 8px;
            margin-bottom: 20px;
            font-size: 14px;
            font-weight: 600;
        }
    </style>
</head>
<body class="railway-ui">
<div class="app ams-shell">
    <jsp:include page="sidebar.jsp" />
    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />
        <div class="main-scroll-content">
            <div class="hero-banner">
                <div>
                    <h1>New Asset Request</h1>
                    <p>Request a new asset for official use.</p>
                </div>
            </div>

            <div class="panel">
                <div class="panel-header">
                    <h2>Request Form</h2>
                </div>

                <% if ("failed".equals(error)) { %>
                    <div class="alert-error">Request could not be added. Please check the details.</div>
                <% } else if ("server".equals(error)) { %>
                    <div class="alert-error">Server error occurred. Please try again.</div>
                <% } else if ("invaliddate".equals(error)) { %>
                    <div class="alert-error">Request date must be today or a previous date.</div>
                <% } else if ("invalidselection".equals(error)) { %>
                    <div class="alert-error">Please select a valid category.</div>
                <% } else if ("access".equals(error)) { %>
                    <div class="alert-error">Your login is not linked to an active employee record.</div>
                <% } %>

                <form action="AddAssetRequestServlet" method="post">
                    
                    <div class="form-group">
                        <label>Asset Category</label>
                        <select name="categoryId" required>
                            <option value="">Select Category</option>
                            <%
                                try (Connection con = DBConnection.getConnection();
                                     PreparedStatement ps = con.prepareStatement(
                                         "SELECT category_id, category_name FROM asset_categories WHERE is_active = 'YES' ORDER BY category_name");
                                     ResultSet rs = ps.executeQuery()) {
                                     
                                     while (rs.next()) {
                            %>
                                        <option value="<%= rs.getInt("category_id") %>">
                                            <%= HtmlEscapeUtil.escape(rs.getString("category_name")) %>
                                        </option>
                            <%       }
                                } catch (Exception e) {
                                    e.printStackTrace();
                                }
                            %>
                        </select>
                    </div>

                    <div class="form-group">
                        <label>Request Date</label>
                        <input type="date" name="requestDate" id="requestDate" value="<%= new java.sql.Date(System.currentTimeMillis()) %>" required>
                    </div>

                    <div class="form-group">
                        <label>Reason / Remarks</label>
                        <input type="text" name="remarks" placeholder="Example: Laptop required for field inspection" required>
                    </div>

                    <button type="submit" class="btn-submit">
                        <i class="fa-solid fa-paper-plane"></i> Submit Request
                    </button>
                </form>
            </div>
        </div>
    </main>
</div>

<script>
    document.addEventListener("DOMContentLoaded", () => {
        const dateInput = document.getElementById('requestDate');
        if (dateInput) {
            const today = new Date().toISOString().split('T')[0];
            dateInput.value = today;
            dateInput.max = today;
        }
    });
</script>

<script src="js/topbar-search.js?v=1"></script>
<script src="js/user-dropdown.js?v=1"></script>
<script src="js/sidebar-role.js?v=1"></script>
<script src="js/ir-body-watermark.js?v=1"></script>
<script src="js/dashboard-actions.js?v=1"></script>
</body>
</html>
