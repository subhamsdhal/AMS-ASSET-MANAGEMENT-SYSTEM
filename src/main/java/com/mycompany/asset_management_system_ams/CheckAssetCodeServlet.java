package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.io.PrintWriter;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "CheckAssetCodeServlet", urlPatterns = {"/CheckAssetCodeServlet"})
public class CheckAssetCodeServlet extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        
        HttpSession session = request.getSession(false);
        // Was checking session attribute "userId" - every other servlet in this
        // codebase (LoginServlet included, the only place that ever sets it) uses
        // "user_id". That mismatch meant this always 401'd for every authenticated
        // user; the calling JS in add_asset.jsp/edit_asset.jsp only processes the
        // response on status 200, so the live "code available/already taken"
        // feedback silently never appeared for anyone - no console error, nothing.
        if (session == null || session.getAttribute("user_id") == null) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            return;
        }

        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");

        String assetCode = request.getParameter("assetCode");
        String assetIdParam = request.getParameter("assetId");
        
        if (assetCode == null || assetCode.trim().isEmpty()) {
            try (PrintWriter out = response.getWriter()) {
                out.print("{\"exists\": false, \"available\": false, \"message\": \"\"}");
            }
            return;
        }

        int assetId = -1;
        if (assetIdParam != null && !assetIdParam.trim().isEmpty()) {
            try {
                assetId = Integer.parseInt(assetIdParam);
            } catch (NumberFormatException e) {
                // Ignore parsing error, default to -1
            }
        }

        AssetDAO dao = new AssetDAO();
        boolean exists = dao.isAssetCodeExists(assetCode, assetId);

        try (PrintWriter out = response.getWriter()) {
            if (exists) {
                out.print("{\"exists\": true, \"available\": false, \"message\": \"This asset code is already allotted to another asset.\"}");
            } else {
                out.print("{\"exists\": false, \"available\": true, \"message\": \"Asset code available.\"}");
            }
        }
    }
}
