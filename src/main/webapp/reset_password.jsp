<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.sql.Connection"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.PasswordResetDAO"%>

<%
    String token = request.getParameter("token");
    String error = request.getParameter("error");

    String errorMessage = null;
    if ("required".equals(error)) {
        errorMessage = "Please fill in both password fields.";
    } else if ("mismatch".equals(error)) {
        errorMessage = "New password and confirm password do not match.";
    } else if ("short".equals(error)) {
        errorMessage = "New password must be at least 6 characters.";
    } else if ("server".equals(error)) {
        errorMessage = "We hit a problem on our end. Please try again.";
    }

    boolean tokenValid = false;
    boolean isActivation = false;

    if (token != null && !token.trim().isEmpty()) {
        Connection con = null;
        try {
            con = DBConnection.getConnection();
            if (con != null) {
                PasswordResetDAO.ensureTable(con);
                PasswordResetDAO.ResolvedToken resolved = PasswordResetDAO.resolveValidToken(con, token, null);
                if (resolved != null) {
                    tokenValid = true;
                    isActivation = PasswordResetDAO.TYPE_ACTIVATION.equals(resolved.tokenType);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            if (con != null) {
                try { con.close(); } catch (Exception ignore) { }
            }
        }
    }
    // NOTE: this check is a display/UX convenience only. ResetPasswordServlet
    // re-validates the token from scratch (existence, expiry, used_at) before
    // it writes anything - a forged or replayed request here still cannot
    // change a password without a token that independently passes that check.
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS | <%= isActivation ? "Set Your Password" : "Reset Your Password" %></title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/login.css?v=28004">
</head>

<body class="login-page">

<div class="page">

    <div class="brand">
        <img src="images/indian-railway-logo.png" alt="Indian Railway Logo">

        <div>
            <h1>IR-AMS</h1>
            <p>Indian Railway<br>Asset Management System</p>
        </div>
    </div>

    <div class="login-area">

        <% if (!tokenValid) { %>

            <div class="login-card">
            <div class="login-card-inner">
                <h2 class="login-title">Link Invalid or Expired</h2>
                <p class="login-subtitle">
                    This link is no longer valid. Reset/activation links expire after a
                    limited time and can only be used once.
                </p>

                <div class="signup-box">
                    <a href="forgot_password.jsp">Request a new link</a>
                    &nbsp;|&nbsp;
                    <a href="login.jsp">Back to Sign In</a>
                </div>
            </div>
            </div>

        <% } else { %>

            <form class="login-card" action="ResetPasswordServlet" method="post" autocomplete="off">
            <div class="login-card-inner">

                <h2 class="login-title"><%= isActivation ? "Set Your Password" : "Reset Your Password" %></h2>
                <p class="login-subtitle">
                    <%= isActivation
                            ? "Choose a password to finish activating your IR-AMS account."
                            : "Choose a new password for your IR-AMS account." %>
                </p>

                <% if (errorMessage != null) { %>
                    <div class="error-box">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        <%= errorMessage %>
                    </div>
                <% } %>

                <input type="hidden" name="token" value="<%= token.replace("\"", "&quot;") %>">

                <div class="form-group">
                    <label>New Password</label>

                    <div class="input-box">
                        <i class="fa-solid fa-lock"></i>

                        <input type="password"
                               id="newPassword"
                               name="newPassword"
                               placeholder="Enter new password"
                               autocomplete="new-password"
                               required>
                    </div>
                </div>

                <div class="form-group">
                    <label>Confirm New Password</label>

                    <div class="input-box">
                        <i class="fa-solid fa-lock"></i>

                        <input type="password"
                               id="confirmPassword"
                               name="confirmPassword"
                               placeholder="Confirm new password"
                               autocomplete="new-password"
                               required>
                    </div>
                </div>

                <button type="submit" class="login-btn">
                    <span class="btn-left">
                        <i class="fa-solid fa-floppy-disk"></i>
                    </span>

                    <span class="btn-text"><%= isActivation ? "Activate Account" : "Reset Password" %></span>

                    <span class="btn-right">&rarr;</span>
                </button>

                <div class="password-note" style="margin-top:16px;font-size:12px;color:#94a3b8;">
                    Password must be at least 6 characters.
                </div>

            </div>
            </form>

        <% } %>

    </div>

</div>

</body>
</html>
