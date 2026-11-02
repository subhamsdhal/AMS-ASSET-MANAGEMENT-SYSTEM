package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;

@WebServlet(name = "ManageQrUrlsServlet", urlPatterns = {"/ManageQrUrlsServlet"})
public class ManageQrUrlsServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        HttpSession session = request.getSession(false);

        if (session == null || session.getAttribute("username") == null || session.getAttribute("role") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        String role = String.valueOf(session.getAttribute("role"));
        if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equalsIgnoreCase(role)) {
            response.sendRedirect("dashboard.jsp?access=denied");
            return;
        }

        String action = request.getParameter("action");
        if (action == null) {
            response.sendRedirect("qr_control_center.jsp");
            return;
        }

        try (Connection con = DBConnection.getConnection()) {
            if ("add".equalsIgnoreCase(action)) {
                String label = request.getParameter("label");
                String providerType = request.getParameter("provider_type");
                String baseUrl = request.getParameter("base_url");

                if (baseUrl == null || baseUrl.trim().isEmpty() || label == null || label.trim().isEmpty()) {
                    response.sendRedirect("qr_control_center.jsp?error=invalid_input#qr-settings");
                    return;
                }
                
                baseUrl = baseUrl.trim();
                if (!baseUrl.startsWith("http://") && !baseUrl.startsWith("https://")) {
                     response.sendRedirect("qr_control_center.jsp?error=invalid_url_scheme#qr-settings");
                     return;
                }
                
                // Ensure table exists just in case
                QrUrlUtil.resolveBaseUrl(request); 

                String sql = "INSERT INTO public_qr_base_urls (label, provider_type, base_url, is_active) VALUES (?, ?, ?, 0)";
                try (PreparedStatement ps = con.prepareStatement(sql)) {
                    ps.setString(1, label.trim());
                    ps.setString(2, providerType);
                    ps.setString(3, baseUrl);
                    ps.executeUpdate();
                }
                response.sendRedirect("qr_control_center.jsp?msg=url_added#qr-settings");

            } else if ("activate".equalsIgnoreCase(action)) {
                String idStr = request.getParameter("id");
                if (idStr != null && !idStr.isEmpty()) {
                    int id = Integer.parseInt(idStr);

                    // Wrapped in a transaction - these two UPDATEs (deactivate all,
                    // then activate the selected one) were previously two separate
                    // auto-committed statements. If the connection dropped between
                    // them, every public QR base URL would be left inactive
                    // (QrUrlUtil.isPublicBaseUrlReady() would then block all QR
                    // generation app-wide until an admin noticed and re-activated
                    // one). Now atomic: either both apply or neither does.
                    con.setAutoCommit(false);
                    try {
                        try (PreparedStatement ps1 = con.prepareStatement("UPDATE public_qr_base_urls SET is_active = 0")) {
                            ps1.executeUpdate();
                        }

                        try (PreparedStatement ps2 = con.prepareStatement("UPDATE public_qr_base_urls SET is_active = 1 WHERE id = ?")) {
                            ps2.setInt(1, id);
                            ps2.executeUpdate();
                        }

                        con.commit();
                    } catch (Exception activateEx) {
                        con.rollback();
                        throw activateEx;
                    } finally {
                        con.setAutoCommit(true);
                    }
                }
                response.sendRedirect("qr_control_center.jsp?msg=url_activated#qr-settings");

            } else if ("delete".equalsIgnoreCase(action)) {
                String idStr = request.getParameter("id");
                if (idStr != null && !idStr.isEmpty()) {
                    int id = Integer.parseInt(idStr);
                    try (PreparedStatement ps = con.prepareStatement("DELETE FROM public_qr_base_urls WHERE id = ?")) {
                        ps.setInt(1, id);
                        ps.executeUpdate();
                    }
                }
                response.sendRedirect("qr_control_center.jsp?msg=url_deleted#qr-settings");
            } else {
                response.sendRedirect("qr_control_center.jsp");
            }
        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
            response.sendRedirect("qr_control_center.jsp?error=db_error#qr-settings");
        }
    }
}
