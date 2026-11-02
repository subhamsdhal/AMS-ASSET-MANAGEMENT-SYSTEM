package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

/**
 * RenewAssetWarrantyServlet - records a warranty renewal and updates the
 * asset's live warranty_expiry, via WarrantyRenewalDAO.recordRenewal().
 *
 * Read-only report access (AUDITOR, via qrViewOps in RoleAccessUtil) is
 * intentionally NOT enough to reach this servlet - only SUPER_ADMIN, ADMIN,
 * and ASSET_MANAGER can renew, matching the mutate-vs-view split already
 * used everywhere else in this app.
 */
@WebServlet(name = "RenewAssetWarrantyServlet", urlPatterns = {"/RenewAssetWarrantyServlet"})
public class RenewAssetWarrantyServlet extends HttpServlet {

    private static final DateTimeFormatter ISO_DATE = DateTimeFormatter.ofPattern("yyyy-MM-dd");

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        request.setCharacterEncoding("UTF-8");

        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        String role = String.valueOf(session.getAttribute("role"));
        boolean allowed = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role) || "ASSET_MANAGER".equals(role);
        if (!allowed) {
            response.sendRedirect("warranty_report.jsp?access=denied");
            return;
        }

        String username = String.valueOf(session.getAttribute("username"));
        int userId = getSessionUserId(session);

        int assetId = parseIntOrDefault(request.getParameter("assetId"), 0);
        if (assetId <= 0) {
            response.sendRedirect("warranty_report.jsp?error=invalid_asset");
            return;
        }

        String newExpiry = clean(request.getParameter("newExpiry"));
        String extensionMonthsRaw = clean(request.getParameter("extensionMonths"));
        String costRaw = clean(request.getParameter("renewalCost"));
        String notes = clean(request.getParameter("notes"));

        Integer extensionMonths = null;
        String currentExpiry = getCurrentExpiry(assetId);

        // Either an explicit new date, or an extension in months from the
        // current expiry (or from today if there's no warranty yet) - the
        // admin fills in whichever is more natural for the paperwork in hand.
        if (newExpiry.isEmpty() && !extensionMonthsRaw.isEmpty()) {
            try {
                int months = Integer.parseInt(extensionMonthsRaw);
                if (months < 1 || months > 240) {
                    response.sendRedirect("renew_warranty.jsp?id=" + assetId + "&error=invalid_extension");
                    return;
                }
                extensionMonths = months;
                LocalDate base = (currentExpiry != null && !currentExpiry.isEmpty())
                        ? LocalDate.parse(currentExpiry.substring(0, 10), ISO_DATE)
                        : LocalDate.now();
                if (base.isBefore(LocalDate.now())) {
                    base = LocalDate.now();
                }
                newExpiry = base.plusMonths(months).format(ISO_DATE);
            } catch (Exception e) {
                response.sendRedirect("renew_warranty.jsp?id=" + assetId + "&error=invalid_extension");
                return;
            }
        }

        if (newExpiry.isEmpty()) {
            response.sendRedirect("renew_warranty.jsp?id=" + assetId + "&error=missing_date");
            return;
        }

        LocalDate parsedNewExpiry;
        try {
            parsedNewExpiry = LocalDate.parse(newExpiry, ISO_DATE);
        } catch (Exception e) {
            response.sendRedirect("renew_warranty.jsp?id=" + assetId + "&error=invalid_date");
            return;
        }

        if (parsedNewExpiry.isBefore(LocalDate.now())) {
            response.sendRedirect("renew_warranty.jsp?id=" + assetId + "&error=date_in_past");
            return;
        }

        double renewalCost = 0.0;
        if (!costRaw.isEmpty()) {
            try {
                renewalCost = Double.parseDouble(costRaw);
                if (renewalCost < 0) {
                    renewalCost = 0.0;
                }
            } catch (Exception e) {
                renewalCost = 0.0;
            }
        }

        if (notes.length() > 1000) {
            notes = notes.substring(0, 1000);
        }

        WarrantyRenewalDAO dao = new WarrantyRenewalDAO();
        boolean success = dao.recordRenewal(assetId, currentExpiry, newExpiry, extensionMonths, renewalCost, notes, userId);

        if (!success) {
            response.sendRedirect("renew_warranty.jsp?id=" + assetId + "&error=server");
            return;
        }

        AuditDAO.log(userId, "RENEW_WARRANTY", "assets", assetId,
                "Warranty renewed by " + username + ". Previous expiry: "
                        + (currentExpiry == null || currentExpiry.isEmpty() ? "none" : currentExpiry)
                        + ", new expiry: " + newExpiry
                        + (renewalCost > 0 ? String.format(", cost: Rs.%.2f", renewalCost) : ""));

        response.sendRedirect("warranty_report.jsp?msg=renewed");
    }

    private String getCurrentExpiry(int assetId) {
        String sql = "SELECT warranty_expiry FROM assets WHERE asset_id = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getString("warranty_expiry");
                }
            }
        } catch (Exception e) {
            // fall through - treated as "no prior warranty on record"
        }
        return null;
    }

    private int getSessionUserId(HttpSession session) {
        Object userIdObj = session.getAttribute("user_id");
        if (userIdObj == null) {
            userIdObj = session.getAttribute("userId");
        }
        if (userIdObj != null) {
            try {
                return Integer.parseInt(String.valueOf(userIdObj));
            } catch (Exception ignored) {
            }
        }
        return 0;
    }

    private int parseIntOrDefault(String value, int fallback) {
        if (value == null) {
            return fallback;
        }
        try {
            return Integer.parseInt(value.trim());
        } catch (Exception e) {
            return fallback;
        }
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
