<%@page contentType="text/html" pageEncoding="UTF-8"%>

<%
    String error = request.getParameter("error");
    String sent = request.getParameter("sent");

    String errorMessage = null;
    if ("required".equals(error)) {
        errorMessage = "Please enter your username or email.";
    } else if ("server".equals(error)) {
        errorMessage = "We hit a problem on our end. Please try again in a moment.";
    } else if ("invalid_token".equals(error)) {
        errorMessage = "That reset link is invalid or has expired. Request a new one below.";
    }

    boolean showConfirmation = "1".equals(sent);
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS | Forgot Password</title>

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

        <% if (showConfirmation) { %>

            <div class="login-card">
            <div class="login-card-inner">
                <h2 class="login-title">Check Your Email</h2>
                <p class="login-subtitle">
                    If an account matches what you entered, we've emailed a password reset link
                    to the address on file. The link expires in 30 minutes.
                </p>

                <div class="signup-box">
                    <a href="login.jsp">&larr; Back to Sign In</a>
                </div>
            </div>
            </div>

        <% } else { %>

            <form class="login-card" action="ForgotPasswordServlet" method="post" autocomplete="off">
            <div class="login-card-inner">

                <h2 class="login-title">Forgot Password</h2>
                <p class="login-subtitle">Enter your username or email and we'll send you a reset link.</p>

                <% if (errorMessage != null) { %>
                    <div class="error-box">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        <%= errorMessage %>
                    </div>
                <% } %>

                <div class="form-group">
                    <label>Username or Email</label>

                    <div class="input-box">
                        <i class="fa-regular fa-user"></i>

                        <input type="text"
                               id="identifier"
                               name="identifier"
                               placeholder="Enter your username or email"
                               autocomplete="off"
                               required>
                    </div>
                </div>

                <button type="submit" class="login-btn">
                    <span class="btn-left">
                        <i class="fa-solid fa-paper-plane"></i>
                    </span>

                    <span class="btn-text">Send Reset Link</span>

                    <span class="btn-right">&rarr;</span>
                </button>

                <div class="signup-box">
                    <a href="login.jsp">&larr; Back to Sign In</a>
                </div>

            </div>
            </form>

        <% } %>

    </div>

</div>

</body>
</html>
