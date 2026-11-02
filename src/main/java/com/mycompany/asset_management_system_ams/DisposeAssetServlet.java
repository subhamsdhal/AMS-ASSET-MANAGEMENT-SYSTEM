package com.mycompany.asset_management_system_ams;

import java.io.IOException;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "DisposeAssetServlet", urlPatterns = {"/DisposeAssetServlet"})
public class DisposeAssetServlet extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        int assetId = parseInt(request.getParameter("id"), 0);

        if (assetId <= 0) {
            response.sendRedirect("assets.jsp?error=failed");
            return;
        }

        response.sendRedirect("dispose_asset.jsp?id=" + assetId);
    }

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        int assetId = 0;

        try {
            request.setCharacterEncoding("UTF-8");

            HttpSession session = request.getSession(false);

            if (session == null
                    || session.getAttribute("username") == null
                    || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = String.valueOf(session.getAttribute("username"));
            String role = String.valueOf(session.getAttribute("role"));

            int userId = getSessionInt(session, "user_id", 1);

            if (userId == 1) {
                userId = getSessionInt(session, "userId", 1);
            }

            if (!RoleAccessUtil.hasAccess(role, request.getRequestURI())) {
                response.sendRedirect("assets.jsp?access=denied");
                return;
            }

            assetId = parseInt(request.getParameter("assetId"), 0);
            String disposalDate = safe(request.getParameter("disposalDate"), "");
            double disposalValue = parseDouble(request.getParameter("disposalValue"), -1);
            String disposalReason = safe(request.getParameter("disposalReason"), "");

            if (assetId <= 0) {
                response.sendRedirect("assets.jsp?error=failed");
                return;
            }

            if (disposalDate.isEmpty() || !DateValidationUtil.isPastOrToday(disposalDate)) {
                response.sendRedirect("dispose_asset.jsp?id=" + assetId + "&error=invaliddate");
                return;
            }

            if (disposalValue < 0 || disposalReason.isEmpty()) {
                response.sendRedirect("dispose_asset.jsp?id=" + assetId + "&error=failed");
                return;
            }

            AssetDAO dao = new AssetDAO();
            Asset asset = dao.getAssetById(assetId);

            if (asset == null) {
                response.sendRedirect("assets.jsp?error=failed");
                return;
            }

            // hasBlockingDisposal (PENDING/COMPLETED only), not hasExistingDisposal
            // (any status) - a REJECTED row must NOT block a fresh submission,
            // since resubmission after rejection is how the maker-checker
            // workflow's reject path is meant to be used.
            if ("DISPOSED".equalsIgnoreCase(asset.getAssetStatus()) || dao.hasBlockingDisposal(assetId)) {
                response.sendRedirect("dispose_asset.jsp?id=" + assetId + "&error=alreadydisposed");
                return;
            }

            if (dao.hasActiveAllocation(assetId)) {
                response.sendRedirect("dispose_asset.jsp?id=" + assetId + "&error=allocated");
                return;
            }

            if (asset.getPurchaseDate() != null && !asset.getPurchaseDate().isEmpty()) {
                if (!DateValidationUtil.isDateNotBefore(disposalDate, asset.getPurchaseDate())) {
                    response.sendRedirect("dispose_asset.jsp?id=" + assetId + "&error=invaliddate");
                    return;
                }
            }

            String[] oldDetails = dao.getDisposalNotificationDetails(assetId);

            // Maker stage only: proposes the disposal (disposal_status='PENDING')
            // without touching assets.asset_status. A SUPER_ADMIN/ADMIN reviewer
            // must separately approve it via ReviewAssetDisposalServlet before the
            // asset actually becomes DISPOSED - see AssetDAO.submitDisposal()'s
            // own javadoc for why (closes the Future Scope maker-checker gap).
            boolean submitted = dao.submitDisposal(
                    assetId,
                    disposalDate,
                    disposalReason,
                    disposalValue,
                    userId,
                    disposalReason
            );

            if (submitted) {

                AuditDAO.log(
                        userId,
                        "DISPOSAL_SUBMITTED",
                        "assets",
                        assetId,
                        "Asset disposal proposed, awaiting review. Asset ID: " + assetId
                        + ", Disposal Date: " + disposalDate
                        + ", Disposal Value: " + disposalValue
                        + ", Reason: " + disposalReason
                        + ", Submitted by: " + username
                );

                sendDisposalEmail(
                        request,
                        oldDetails,
                        assetId,
                        username,
                        role
                );

                response.sendRedirect("assets.jsp?msg=disposalsubmitted");

            } else {
                response.sendRedirect("dispose_asset.jsp?id=" + assetId + "&error=failed");
            }

        } catch (Exception e) {
            e.printStackTrace();

            if (assetId > 0) {
                response.sendRedirect("dispose_asset.jsp?id=" + assetId + "&error=server");
            } else {
                response.sendRedirect("assets.jsp?error=server");
            }
        }
    }

    private void sendDisposalEmail(
            HttpServletRequest request,
            String[] details,
            int assetId,
            String username,
            String role
    ) {
        try {
            if (details == null) {
                return;
            }

            String assetCode = getArrayValue(details, 1, "N/A");
            String assetName = getArrayValue(details, 2, "N/A");
            String categoryName = getArrayValue(details, 3, "N/A");
            String vendorName = getArrayValue(details, 4, "N/A");
            String serialNumber = getArrayValue(details, 5, "N/A");
            String location = getArrayValue(details, 6, "N/A");
            String purchaseDate = getArrayValue(details, 7, "N/A");
            String purchaseCost = getArrayValue(details, 8, "0.0");
            String warrantyExpiry = getArrayValue(details, 9, "N/A");
            String oldAssetStatus = getArrayValue(details, 10, "N/A");

            String employeeEmail = getArrayValue(details, 11, "");
            String employeeName = getArrayValue(details, 12, "Not currently allocated");
            String employeeCode = getArrayValue(details, 13, "N/A");
            String departmentName = getArrayValue(details, 14, "N/A");

            // "DISPOSAL_SUBMITTED" (maker's proposal, notify the SUPER_ADMIN/ADMIN
            // reviewers) - not "DISPOSED", which is now reserved for
            // ReviewAssetDisposalServlet's actual approval notice. The asset is
            // NOT disposed yet at this point; see AssetDAO.submitDisposal().
            NotificationEventService.EmailRouting routing = NotificationEventService.buildAssetRecipients("DISPOSAL_SUBMITTED", assetId);
            String recipientEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            String subject = "IR-AMS | Asset Disposal Proposed - Awaiting Review | Asset #" + assetId;

            // Deferred finding from the Asset Registration/Master audit, fixed here:
            // these are all DB-sourced free-text fields (asset/category/vendor/employee
            // names, editable by Asset Manager+) landing straight in an HTML email body
            // with no escaping. HtmlEscapeUtil.escape() is a no-op on already-plain text,
            // so this is a pure hardening change, not a display change for normal data.
            String detailsTable = "<tr><th>Asset ID:</th><td>" + assetId + "</td></tr>"
                    + "<tr><th>Asset:</th><td>" + HtmlEscapeUtil.escape(assetName) + " (" + HtmlEscapeUtil.escape(assetCode) + ")</td></tr>"
                    + "<tr><th>Category:</th><td>" + HtmlEscapeUtil.escape(categoryName) + "</td></tr>"
                    + "<tr><th>Vendor:</th><td>" + HtmlEscapeUtil.escape(vendorName) + "</td></tr>"
                    + "<tr><th>Serial Number:</th><td>" + HtmlEscapeUtil.escape(serialNumber) + "</td></tr>"
                    + "<tr><th>Location:</th><td>" + HtmlEscapeUtil.escape(location) + "</td></tr>"
                    + "<tr><th>Purchase Date:</th><td>" + HtmlEscapeUtil.escape(purchaseDate) + "</td></tr>"
                    + "<tr><th>Purchase Cost:</th><td>Rs. " + HtmlEscapeUtil.escape(purchaseCost) + "</td></tr>"
                    + "<tr><th>Warranty Expiry:</th><td>" + HtmlEscapeUtil.escape(warrantyExpiry) + "</td></tr>"
                    + "<tr><th>Current Asset Status:</th><td>" + HtmlEscapeUtil.escape(oldAssetStatus) + " (unchanged until reviewed)</td></tr>"
                    + "<tr><th>Currently Allocated To:</th><td>" + HtmlEscapeUtil.escape(employeeName) + " (" + HtmlEscapeUtil.escape(employeeCode) + ")</td></tr>"
                    + "<tr><th>Department:</th><td>" + HtmlEscapeUtil.escape(departmentName) + "</td></tr>";

            String actionNote = "This disposal proposal is awaiting review. The asset's status will not change to DISPOSED "
                    + "unless a Super Admin or Admin approves it. Please log in to IR-AMS to review this proposal.";

            String body = NotificationHelper.buildHtmlEmail("", "Asset Disposal Proposed", detailsTable, actionNote);

            NotificationHelper.sendDisposalAlert(
                    request.getServletContext(),
                    assetId,
                    recipientEmail,
                    ccEmail,
                    "",
                    subject,
                    body
            );

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private int getSessionInt(HttpSession session, String key, int fallback) {
        try {
            Object value = session.getAttribute(key);

            if (value == null) {
                return fallback;
            }

            return Integer.parseInt(String.valueOf(value));

        } catch (Exception e) {
            return fallback;
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

    private double parseDouble(String value, double fallback) {
        try {
            if (value == null || value.trim().isEmpty()) {
                return fallback;
            }

            return Double.parseDouble(value.trim());

        } catch (Exception e) {
            return fallback;
        }
    }

    private String getArrayValue(String[] array, int index, String fallback) {
        if (array == null || index < 0 || index >= array.length) {
            return fallback;
        }

        return safe(array[index], fallback);
    }

    private String safe(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }

        return value.trim();
    }
}
