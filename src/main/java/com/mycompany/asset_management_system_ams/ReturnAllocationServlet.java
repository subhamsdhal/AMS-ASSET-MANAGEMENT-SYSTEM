package com.mycompany.asset_management_system_ams;

import java.io.IOException;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "ReturnAllocationServlet", urlPatterns = {"/ReturnAllocationServlet"})
public class ReturnAllocationServlet extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        try {
            HttpSession session = request.getSession(false);

            if (session == null
                    || session.getAttribute("username") == null
                    || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String role = String.valueOf(session.getAttribute("role"));

            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equalsIgnoreCase(role)
                    && !"EMPLOYEE".equalsIgnoreCase(role)) {
                response.sendRedirect("allocation.jsp?access=denied");
                return;
            }

            String allocationId = request.getParameter("id");

            if (allocationId == null || allocationId.trim().isEmpty()) {
                allocationId = request.getParameter("allocationId");
            }

            if (allocationId == null || allocationId.trim().isEmpty()) {
                response.sendRedirect("allocation.jsp?msg=returnfailed");
                return;
            }

            int cleanAllocationId = parseInt(allocationId, 0);

            if (cleanAllocationId <= 0) {
                response.sendRedirect("allocation.jsp?msg=returnfailed");
                return;
            }

            response.sendRedirect("add_return.jsp?allocationId=" + cleanAllocationId);

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("allocation.jsp?msg=returnfailed");
        }
    }

    private int parseInt(String value, int fallback) {
        try {
            if (value == null || value.trim().isEmpty()) {
                return fallback;
            }

            return Integer.parseInt(value.trim());
        } catch (Exception e) {
            return fallback;
        }
    }
}
