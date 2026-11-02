package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import jakarta.servlet.Filter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.FilterConfig;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;
import jakarta.servlet.annotation.WebFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebFilter(filterName = "RoleAuthorizationFilter", urlPatterns = {"/*"})
public class RoleAuthorizationFilter implements Filter {

    @Override
    public void init(FilterConfig filterConfig) throws ServletException {
        // Initialization if needed
    }

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {
            
        HttpServletRequest req = (HttpServletRequest) request;
        HttpServletResponse res = (HttpServletResponse) response;
        
        String path = req.getRequestURI();
        
        // Skip filtering for static resources and public endpoints to avoid infinite loops.
        // Includes the pre-authentication account-recovery/activation flow, which by
        // definition must work for visitors who have no session yet.
        if (path.endsWith("/login.jsp") || path.endsWith("/LoginServlet") || path.endsWith("/logout.jsp") ||
            path.endsWith("/forgot_password.jsp") || path.endsWith("/ForgotPasswordServlet") ||
            path.endsWith("/reset_password.jsp") || path.endsWith("/ResetPasswordServlet") ||
            path.contains("/css/") || path.contains("/js/") || path.contains("/images/") ||
            path.endsWith(".html") || path.endsWith(".png") || path.endsWith(".jpg")) {
            chain.doFilter(request, response);
            return;
        }
        
        HttpSession session = req.getSession(false);
        String role = (session != null && session.getAttribute("role") != null) 
                        ? session.getAttribute("role").toString() : null;

        // Apply Default Deny logic from RoleAccessUtil
        if (!RoleAccessUtil.hasAccess(role, path)) {
            // Unauthorized access attempt
            if (role == null) {
                // Not logged in
                res.sendRedirect(req.getContextPath() + "/login.jsp");
            } else {
                // Logged in but forbidden
                res.sendError(HttpServletResponse.SC_FORBIDDEN, "Access Denied: You do not have permission to view this resource.");
            }
            return;
        }

        // Access granted, proceed
        chain.doFilter(request, response);
    }

    @Override
    public void destroy() {
        // Cleanup if needed
    }
}
