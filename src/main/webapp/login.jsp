<%@page contentType="text/html" pageEncoding="UTF-8"%>

<%
    String error = request.getParameter("error");
    String msg = request.getParameter("msg");

    // Echo the previously-submitted username back into the form after a failed
    // login so the user doesn't have to retype it. HTML-escaped since it is
    // untrusted request input being written back into an attribute.
    String submittedUsername = request.getParameter("username");
    String usernameValue = submittedUsername == null ? "" : escapeHtml(submittedUsername);

    String errorMessage = null;
    if ("invalid".equals(error)) {
        errorMessage = "Invalid username or password";
    } else if ("server".equals(error)) {
        errorMessage = "We hit a problem on our end while signing you in. Please try again in a moment.";
    } else if ("locked".equals(error)) {
        errorMessage = "Too many failed attempts. Please wait a few minutes and try again.";
    } else if (error != null) {
        errorMessage = "Invalid username or password";
    }

    String successMessage = null;
    if ("password_reset_success".equals(msg)) {
        successMessage = "Your password has been reset. Please sign in with your new password.";
    } else if ("account_activated".equals(msg)) {
        successMessage = "Your account is ready. Please sign in.";
    }
%>

<%!
    // Minimal HTML attribute/text escaper - avoids pulling in a dependency for
    // one call site. Escapes the characters that matter inside an HTML
    // attribute value and inside text content.
    private String escapeHtml(String value) {
        if (value == null) {
            return "";
        }
        return value.replace("&", "&amp;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;")
                .replace("<", "&lt;")
                .replace(">", "&gt;");
    }
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS | Secure Login</title>

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

        <form class="login-card" action="LoginServlet" method="post" autocomplete="off" id="loginForm">
        <div class="login-card-inner">

            <h2 class="login-title">Welcome</h2>
            <p class="login-subtitle">Sign in to continue to your dashboard</p>

            <% if (errorMessage != null) { %>
                <div class="error-box">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    <%= errorMessage %>
                </div>
            <% } %>

            <% if (successMessage != null) { %>
                <div class="success-box">
                    <i class="fa-solid fa-circle-check"></i>
                    <%= successMessage %>
                </div>
            <% } %>

            <div class="form-group">
                <label>Username</label>

                <div class="input-box">
                    <i class="fa-regular fa-user"></i>

                    <input type="text"
                           id="username"
                           name="username"
                           placeholder="Enter your username"
                           autocomplete="off"
                           value="<%= usernameValue %>"
                           required>
                </div>
            </div>

            <div class="form-group">
                <label>Password</label>

                <div class="input-box">
                    <i class="fa-solid fa-lock"></i>

                    <input type="password"
                           id="password"
                           name="password"
                           placeholder="Enter your password"
                           autocomplete="new-password"
                           value=""
                           required>

                    <button type="button" class="eye-btn" onclick="togglePassword()">
                        <i id="eyeIcon" class="fa-regular fa-eye"></i>
                    </button>
                </div>
            </div>

            <div class="options">
                <label class="remember">
                    <input type="checkbox" name="remember" checked>
                    Remember me
                </label>

                <a href="forgot_password.jsp">Forgot password?</a>
            </div>

            <button type="submit" class="login-btn" id="loginSubmitBtn">
                <span class="btn-left">
                    <i class="fa-solid fa-right-to-bracket"></i>
                </span>

                <span class="btn-text">Sign In</span>

                <span class="btn-right">→</span>
            </button>

        </div>
        </form>

    </div>

</div>

<script>
    function togglePassword() {
        const password = document.getElementById("password");
        const eyeIcon = document.getElementById("eyeIcon");

        if (password.type === "password") {
            password.type = "text";
            eyeIcon.classList.remove("fa-eye");
            eyeIcon.classList.add("fa-eye-slash");
        } else {
            password.type = "password";
            eyeIcon.classList.remove("fa-eye-slash");
            eyeIcon.classList.add("fa-eye");
        }
    }

    // Prevent double-submit (duplicate POSTs / duplicate audit-log and
    // lockout-counter entries on a slow connection) and give the user visible
    // feedback that the click registered.
    document.getElementById("loginForm").addEventListener("submit", function (submitEvent) {
        const btn = document.getElementById("loginSubmitBtn");
        if (btn.dataset.submitting === "true") {
            submitEvent.preventDefault();
            return;
        }
        btn.dataset.submitting = "true";
        btn.querySelector(".btn-text").textContent = "Signing in…";
        btn.disabled = true;
    });
</script>

</body>
</html>