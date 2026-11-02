package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletContext;

public class NotificationEventService {

    private NotificationEventService() {
    }

    public static void sendLoginSuccessNotice(
            ServletContext context,
            int userId,
            String username,
            String userEmail,
            String role,
            Integer employeeId,
            String remoteAddress,
            String userAgent
    ) {
        try {
            String empCode = "N/A";
            String empName = "N/A";
            String designation = "N/A";
            String dynamicEmail = "";

            if (employeeId != null && employeeId > 0) {
                try (java.sql.Connection con = DBConnection.getConnection();
                     java.sql.PreparedStatement ps = con.prepareStatement("SELECT employee_code, employee_name, designation, email FROM employees WHERE employee_id = ?")) {
                    ps.setInt(1, employeeId);
                    try (java.sql.ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            // htmlSafe: these three are only ever displayed in the HTML
                            // body below, never used for routing/subject - escape here.
                            empCode = htmlSafe(rs.getString("employee_code"), "N/A");
                            empName = htmlSafe(rs.getString("employee_name"), "N/A");
                            designation = htmlSafe(rs.getString("designation"), "N/A");
                            dynamicEmail = safe(rs.getString("email"), "");
                        }
                    }
                } catch (Exception ex) {
                    System.err.println("Warning: Failed to fetch employee details for login notification: " + ex.getMessage());
                }
            } else if (userId > 0) {
                try (java.sql.Connection con = DBConnection.getConnection();
                     java.sql.PreparedStatement ps = con.prepareStatement("SELECT e.employee_code, e.employee_name, e.designation, e.email FROM users u JOIN employees e ON u.employee_id = e.employee_id WHERE u.user_id = ?")) {
                    ps.setInt(1, userId);
                    try (java.sql.ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            empCode = htmlSafe(rs.getString("employee_code"), "N/A");
                            empName = htmlSafe(rs.getString("employee_name"), "N/A");
                            designation = htmlSafe(rs.getString("designation"), "N/A");
                            dynamicEmail = safe(rs.getString("email"), "");
                        }
                    }
                } catch (Exception ex) {
                    System.err.println("Warning: Failed to fetch employee details by userId for login notification: " + ex.getMessage());
                }
            }
            
            if (dynamicEmail.isEmpty()) {
                System.out.println("Warning: Missing dynamic employee email for user " + username);
            }

            String superAdminRoleEmail = NotificationRecipientResolver.getPrimaryEmailByRole("SUPER_ADMIN");
            String departmentHeadEmail = NotificationRecipientResolver.getPrimaryEmailByRole("DEPARTMENT_HEAD");

            String toEmail = "";
            String ccEmail = "";

            String r = safe(role, "").toUpperCase();
            if ("SUPER_ADMIN".equals(r) || "ADMIN".equals(r)) {
                toEmail = superAdminRoleEmail;
                ccEmail = "";
            } else if ("ASSET_MANAGER".equals(r)) {
                toEmail = dynamicEmail;
                ccEmail = superAdminRoleEmail;
            } else if ("DEPARTMENT_HEAD".equals(r)) {
                toEmail = dynamicEmail;
                ccEmail = superAdminRoleEmail;
            } else if ("AUDITOR".equals(r)) {
                toEmail = dynamicEmail;
                ccEmail = superAdminRoleEmail;
            } else if ("EMPLOYEE".equals(r)) {
                toEmail = dynamicEmail;
                ccEmail = buildCc("", superAdminRoleEmail, departmentHeadEmail);
            } else {
                toEmail = dynamicEmail;
                ccEmail = superAdminRoleEmail;
            }

            // dynamicEmail itself stays unescaped (it's used for routing/replyTo
            // above); only this display copy, headed into the HTML body, is escaped.
            String displayEmail = htmlSafe(dynamicEmail, "Not available");
            String subject = "IR-AMS Login Notice | " + safe(username, "User") + " | " + r;

            String detailsTable = "<tr><th>Status:</th><td>Login Successful</td></tr>"
                    + "<tr><th>Module:</th><td>Authentication</td></tr>"
                    + "<tr><th>User ID:</th><td>" + userId + "</td></tr>"
                    + "<tr><th>Username:</th><td>" + htmlSafe(username, "N/A") + "</td></tr>"
                    + "<tr><th>Role:</th><td>" + htmlSafe(r, "N/A") + "</td></tr>"
                    + "<tr><th>Employee Code:</th><td>" + empCode + "</td></tr>"
                    + "<tr><th>Employee Name:</th><td>" + empName + "</td></tr>"
                    + "<tr><th>Designation:</th><td>" + designation + "</td></tr>"
                    + "<tr><th>Account Email:</th><td>" + displayEmail + "</td></tr>"
                    + "<tr><th>Source IP:</th><td>" + htmlSafe(remoteAddress, "N/A") + "</td></tr>"
                    // userAgent is the raw HTTP User-Agent request header - fully
                    // attacker-controlled, reachable pre-auth on every login attempt.
                    // The highest-real-risk sink in this file before this fix.
                    + "<tr><th>User Agent:</th><td>" + htmlSafe(userAgent, "N/A") + "</td></tr>";

            String actionNote = "This login activity was recorded by Railway AMS.";

            String body = NotificationHelper.buildHtmlEmail("", "LOGIN NOTICE", detailsTable, actionNote);

            NotificationHelper.sendNotification(
                    context,
                    "LOGIN_SUCCESS_ALERT",
                    NotificationHelper.MODULE_ADMIN_SECURITY,
                    userId,
                    toEmail,
                    ccEmail,
                    dynamicEmail, // Use dynamicEmail for replyTo if applicable
                    subject,
                    body
            );
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public static void sendAssetAddedNotice(
            ServletContext context,
            int referenceId,
            String assetCode,
            String assetName,
            int categoryId,
            int vendorId,
            String serialNumber,
            String location,
            String purchaseDate,
            String warrantyExpiry,
            double purchaseCost,
            String addedBy,
            String role,
            String replyToEmail
    ) {
        try {
            EmailRouting routing = buildAssetRecipients("ADDED", referenceId);
            String toEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            String subject = "IR-AMS Asset Added | " + safe(assetCode, "New Asset");

            String detailsTable = "<tr><th>Status:</th><td>New Asset Added</td></tr>"
                    + "<tr><th>Module:</th><td>Assets</td></tr>"
                    + "<tr><th>Reference ID:</th><td>" + referenceId + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>ASSET DETAILS</b></td></tr>"
                    + "<tr><th>Asset Code:</th><td>" + htmlSafe(assetCode, "N/A") + "</td></tr>"
                    + "<tr><th>Asset Name:</th><td>" + htmlSafe(assetName, "N/A") + "</td></tr>"
                    + "<tr><th>Category ID:</th><td>" + categoryId + "</td></tr>"
                    + "<tr><th>Supplier ID:</th><td>" + vendorId + "</td></tr>"
                    + "<tr><th>Serial Number:</th><td>" + htmlSafe(serialNumber, "N/A") + "</td></tr>"
                    + "<tr><th>Location:</th><td>" + htmlSafe(location, "N/A") + "</td></tr>"
                    + "<tr><th>Purchase Date:</th><td>" + htmlSafe(purchaseDate, "N/A") + "</td></tr>"
                    + "<tr><th>Warranty Till:</th><td>" + htmlSafe(warrantyExpiry, "N/A") + "</td></tr>"
                    + "<tr><th>Purchase Cost:</th><td>Rs. " + purchaseCost + "</td></tr>"
                    + "<tr><th>Initial Status:</th><td>AVAILABLE</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>ACTION DETAILS</b></td></tr>"
                    + "<tr><th>Added By:</th><td>" + htmlSafe(addedBy, "N/A") + "</td></tr>"
                    + "<tr><th>Role:</th><td>" + htmlSafe(formatRole(role), "N/A") + "</td></tr>"
                    + "<tr><th>Account:</th><td>" + htmlSafe(replyToEmail, "N/A") + "</td></tr>";
            
            String actionNote = "The new asset is now available in the Railway AMS asset register.";

            String body = NotificationHelper.buildHtmlEmail("", "ASSET ADDITION NOTICE", detailsTable, actionNote);

            NotificationHelper.sendNotification(
                    context,
                    "ASSET_ADDED_ALERT",
                    "ASSETS",
                    referenceId,
                    toEmail,
                    ccEmail,
                    replyToEmail,
                    subject,
                    body
            );
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public static void sendAssetUpdatedNotice(
            ServletContext context,
            int assetId,
            String assetCode,
            String assetName,
            int categoryId,
            int vendorId,
            String serialNumber,
            String location,
            String purchaseDate,
            String warrantyExpiry,
            double purchaseCost,
            String status,
            String updatedBy,
            String role,
            String replyToEmail
    ) {
        try {
            String action = "UPDATED";
            if ("AVAILABLE".equalsIgnoreCase(status) || "ALLOCATED".equalsIgnoreCase(status)) {
                action = "STATUS_CHANGED_NORMAL";
            } else if ("UNDER_MAINTENANCE".equalsIgnoreCase(status)) {
                action = "UNDER_MAINTENANCE";
            } else if ("DAMAGED".equalsIgnoreCase(status) || "LOST".equalsIgnoreCase(status)) {
                action = "DAMAGED";
            } else if ("DISPOSED".equalsIgnoreCase(status)) {
                action = "DISPOSED";
            }
            
            EmailRouting routing = buildAssetRecipients(action, assetId);
            String toEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            String subject = "IR-AMS Asset Updated | " + safe(assetCode, "Asset") + " | Asset ID " + assetId;

            String detailsTable = "<tr><th>Status:</th><td>Asset Record Updated</td></tr>"
                    + "<tr><th>Module:</th><td>Assets</td></tr>"
                    + "<tr><th>Asset ID:</th><td>" + assetId + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>UPDATED ASSET DETAILS</b></td></tr>"
                    + "<tr><th>Asset Code:</th><td>" + htmlSafe(assetCode, "N/A") + "</td></tr>"
                    + "<tr><th>Asset Name:</th><td>" + htmlSafe(assetName, "N/A") + "</td></tr>"
                    + "<tr><th>Category ID:</th><td>" + categoryId + "</td></tr>"
                    + "<tr><th>Supplier ID:</th><td>" + vendorId + "</td></tr>"
                    + "<tr><th>Serial Number:</th><td>" + htmlSafe(serialNumber, "N/A") + "</td></tr>"
                    + "<tr><th>Location:</th><td>" + htmlSafe(location, "N/A") + "</td></tr>"
                    + "<tr><th>Purchase Date:</th><td>" + htmlSafe(purchaseDate, "N/A") + "</td></tr>"
                    + "<tr><th>Warranty Till:</th><td>" + htmlSafe(warrantyExpiry, "N/A") + "</td></tr>"
                    + "<tr><th>Purchase Cost:</th><td>Rs. " + purchaseCost + "</td></tr>"
                    + "<tr><th>Asset Status:</th><td>" + htmlSafe(status, "N/A") + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>ACTION DETAILS</b></td></tr>"
                    + "<tr><th>Updated By:</th><td>" + htmlSafe(updatedBy, "N/A") + "</td></tr>"
                    + "<tr><th>Role:</th><td>" + htmlSafe(formatRole(role), "N/A") + "</td></tr>"
                    + "<tr><th>Account:</th><td>" + htmlSafe(replyToEmail, "N/A") + "</td></tr>";
            
            String actionNote = "Please review the asset register if this change was not expected.";

            String body = NotificationHelper.buildHtmlEmail("", "ASSET UPDATE NOTICE", detailsTable, actionNote);

            NotificationHelper.sendNotification(
                    context,
                    "ASSET_UPDATED_ALERT",
                    "ASSETS",
                    assetId,
                    toEmail,
                    ccEmail,
                    replyToEmail,
                    subject,
                    body
            );
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public static void sendCategoryUpdatedNotice(
            ServletContext context,
            int categoryId,
            String categoryName,
            String status,
            String updatedBy,
            String role,
            String replyToEmail
    ) {
        String detailsTable = "<tr><th>Category ID:</th><td>" + categoryId + "</td></tr>"
                + "<tr><th>Category:</th><td>" + htmlSafe(categoryName, "N/A") + "</td></tr>"
                + "<tr><th>Status:</th><td>" + htmlSafe(status, "N/A") + "</td></tr>"
                + "<tr><th>Updated By:</th><td>" + htmlSafe(updatedBy, "N/A") + "</td></tr>"
                + "<tr><th>Role:</th><td>" + htmlSafe(formatRole(role), "N/A") + "</td></tr>";

        sendMasterChangeNotice(
                context,
                "CATEGORY_UPDATED_ALERT",
                "CATEGORIES",
                categoryId,
                "IR-AMS Category Updated | " + safe(categoryName, "Category"),
                detailsTable,
                "Category record updated in Railway AMS.",
                replyToEmail
        );
    }

    public static void sendVendorUpdatedNotice(
            ServletContext context,
            int vendorId,
            String vendorName,
            String contactPerson,
            String email,
            String phone,
            String updatedBy,
            String role,
            String replyToEmail
    ) {
        String detailsTable = "<tr><th>Supplier ID:</th><td>" + vendorId + "</td></tr>"
                + "<tr><th>Supplier Name:</th><td>" + htmlSafe(vendorName, "N/A") + "</td></tr>"
                + "<tr><th>Contact Person:</th><td>" + htmlSafe(contactPerson, "N/A") + "</td></tr>"
                + "<tr><th>Email:</th><td>" + htmlSafe(email, "N/A") + "</td></tr>"
                + "<tr><th>Phone:</th><td>" + htmlSafe(phone, "N/A") + "</td></tr>"
                + "<tr><th>Updated By:</th><td>" + htmlSafe(updatedBy, "N/A") + "</td></tr>"
                + "<tr><th>Role:</th><td>" + htmlSafe(formatRole(role), "N/A") + "</td></tr>";

        sendMasterChangeNotice(
                context,
                "SUPPLIER_UPDATED_ALERT",
                "SUPPLIERS",
                vendorId,
                "IR-AMS Supplier Updated | " + safe(vendorName, "Supplier"),
                detailsTable,
                "Supplier record updated in Railway AMS.",
                replyToEmail
        );
    }

    private static void sendMasterChangeNotice(
            ServletContext context,
            String notificationType,
            String moduleName,
            int referenceId,
            String subject,
            String detailsTable,
            String actionNote,
            String replyToEmail
    ) {
        try {
            EmailRouting routing = buildMasterDataRecipients("UPDATED");
            String toEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            String body = NotificationHelper.buildHtmlEmail("", "Master Record Update", detailsTable, actionNote);

            NotificationHelper.sendNotification(
                    context,
                    notificationType,
                    moduleName,
                    referenceId,
                    toEmail,
                    ccEmail,
                    replyToEmail,
                    subject,
                    body
            );
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private static String getAssetOperationsRecipient() {
        String assetManagerEmail = NotificationRecipientResolver.getPrimaryEmailByRole("ASSET_MANAGER");

        if (!isBlank(assetManagerEmail)) {
            return assetManagerEmail;
        }

        return NotificationRecipientResolver.getPrimaryEmailByRole("SUPER_ADMIN");
    }

    private static String getFallbackEmail(String first, String second) {
        if (!isBlank(first)) {
            return first;
        }

        return safe(second, "");
    }

    public static String buildCc(String exclude, String... emails) {
        String result = "";
        if (emails != null) {
            for (String email : emails) {
                result = addUniqueEmail(result, email, exclude);
            }
        }
        return result;
    }

    private static String addUniqueEmail(String current, String email, String exclude) {
        String cleanEmail = safe(email, "");

        if (cleanEmail.isEmpty()) {
            return current;
        }

        if (!safe(exclude, "").isEmpty() && cleanEmail.equalsIgnoreCase(exclude.trim())) {
            return current;
        }

        if (current == null || current.trim().isEmpty()) {
            return cleanEmail;
        }

        String[] existing = current.split(",");
        for (String item : existing) {
            if (cleanEmail.equalsIgnoreCase(item.trim())) {
                return current;
            }
        }

        return current + "," + cleanEmail;
    }

    private static boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    private static String safe(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }

        return value.trim();
    }

    /**
     * Same null/blank handling as safe(), plus HTML-escaping - for values that
     * land inside an email's HTML <td> cells, as opposed to a subject line or
     * an email address (both of which safe() alone is correct for; escaping a
     * subject would show literal "&amp;" etc. to the recipient instead of
     * fixing anything, since subjects are plain text, not rendered as HTML).
     *
     * Was the deferred cross-cutting finding from the Asset Registration/Master
     * module audit: every send*Notice method here concatenated DB fields -
     * asset code, asset name, employee name, and (worst case) the raw HTTP
     * User-Agent header in sendLoginSuccessNotice - directly into HTML email
     * bodies with zero escaping. An asset code containing "<img src=x
     * onerror=...>" would render as live HTML in most desktop mail clients
     * that still execute inline handlers, or at minimum break the email's
     * layout; a crafted User-Agent header is fully attacker-controlled and
     * needed no authenticated access at all to reach this sink.
     */
    private static String htmlSafe(String value, String fallback) {
        return HtmlEscapeUtil.escape(value, fallback);
    }

    private static String formatRole(String role) {
        if (role == null || role.trim().isEmpty()) {
            return "N/A";
        }

        return role.trim().replace("_", " ");
    }

    public static class EmailRouting {
        private String toEmail;
        private String ccEmail;
        public EmailRouting(String toEmail, String ccEmail) {
            this.toEmail = safe(toEmail, "");
            this.ccEmail = safe(ccEmail, "");
        }
        public String getToEmail() { return toEmail; }
        public String getCcEmail() { return ccEmail; }
    }

    public static EmailRouting buildAssetRecipients(String action, int assetId) {
        String assetManager = NotificationRecipientResolver.getPrimaryEmailByRole("ASSET_MANAGER");
        String superAdmin = NotificationRecipientResolver.getPrimaryEmailByRole("SUPER_ADMIN");
        String auditor = NotificationRecipientResolver.getPrimaryEmailByRole("AUDITOR");
        
        String to = "";
        String cc = "";
        
        switch (action) {
            case "ADDED":
            case "UPDATED":
            case "WARRANTY_EXPIRING":
                to = assetManager;
                cc = buildCc("", to, superAdmin);
                break;
            case "STATUS_CHANGED_NORMAL":
                to = assetManager;
                cc = "";
                break;
            case "UNDER_MAINTENANCE":
                to = assetManager;
                String deptHeadMaint = NotificationRecipientResolver.getDepartmentHeadEmailByAssetId(assetId);
                cc = buildCc("", to, superAdmin, deptHeadMaint);
                break;
            case "DAMAGED":
                to = assetManager;
                String deptHeadDamaged = NotificationRecipientResolver.getDepartmentHeadEmailByAssetId(assetId);
                cc = buildCc("", to, superAdmin, auditor, deptHeadDamaged);
                break;
            case "DISPOSAL_SUBMITTED":
                // Maker's proposal (asset_disposal.disposal_status='PENDING') -
                // routed to the SUPER_ADMIN/ADMIN reviewer tier, cc'ing the Asset
                // Manager tier as the likely maker, so both sides see the same
                // notice. Distinct from "DISPOSED" below, which only fires once
                // a reviewer actually approves it.
                to = superAdmin;
                cc = buildCc("", to, assetManager);
                break;
            case "DISPOSAL_REJECTED":
                // Reviewer rejected the proposal - notify the maker tier; the
                // asset was never touched, so no auditor cc is needed here.
                to = assetManager;
                cc = buildCc("", to, superAdmin);
                break;
            case "DISPOSED":
                to = superAdmin;
                cc = buildCc("", to, assetManager, auditor);
                break;
        }
        return new EmailRouting(to, cc);
    }

    public static EmailRouting buildEmployeeRecipients(String action, int employeeId) {
        String superAdmin = NotificationRecipientResolver.getPrimaryEmailByRole("SUPER_ADMIN");
        String assetManager = NotificationRecipientResolver.getPrimaryEmailByRole("ASSET_MANAGER");
        
        String employeeEmail = NotificationRecipientResolver.getEmployeeEmailByEmployeeId(employeeId);
        String deptHead = NotificationRecipientResolver.getDepartmentHeadEmailByEmployeeId(employeeId);
        if (deptHead.isEmpty()) deptHead = NotificationRecipientResolver.getPrimaryEmailByRole("DEPARTMENT_HEAD");
        
        String to = "";
        String cc = "";
        
        switch (action) {
            case "ADDED":
            case "STATUS_CHANGED":
                to = employeeEmail;
                cc = buildCc("", to, deptHead, superAdmin);
                break;
            case "UPDATED":
                to = employeeEmail;
                cc = buildCc("", to, deptHead);
                break;
            case "DISABLED_DELETED":
                to = superAdmin;
                cc = buildCc("", to, deptHead, assetManager);
                break;
            case "LOGIN_CREATED":
                to = employeeEmail;
                cc = buildCc("", to, superAdmin);
                break;
            case "TRANSFERRED":
                // deptHead here still resolves to the OLD department (caller
                // invokes this before updating employees.department_id) - the new
                // department head is looked up and appended separately by
                // TransferEmployeeServlet, since this method only knows one
                // department per employee.
                to = employeeEmail;
                cc = buildCc("", to, deptHead, superAdmin, assetManager);
                break;
            case "RETIRED":
                to = superAdmin;
                cc = buildCc("", to, deptHead, assetManager);
                break;
        }
        return new EmailRouting(to, cc);
    }

    public static EmailRouting buildDepartmentRecipients(String action, int departmentId) {
        String superAdmin = NotificationRecipientResolver.getPrimaryEmailByRole("SUPER_ADMIN");
        String assetManager = NotificationRecipientResolver.getPrimaryEmailByRole("ASSET_MANAGER");
        String auditor = NotificationRecipientResolver.getPrimaryEmailByRole("AUDITOR");
        
        String deptHead = NotificationRecipientResolver.getDepartmentHeadEmailByDepartmentId(departmentId);
        
        String to = "";
        String cc = "";
        
        switch (action) {
            case "ADDED":
                to = superAdmin;
                cc = buildCc("", to, assetManager);
                break;
            case "UPDATED":
                to = superAdmin;
                cc = buildCc("", to, assetManager, deptHead);
                break;
            case "HEAD_CHANGED":
                to = deptHead;
                cc = buildCc("", to, superAdmin, assetManager);
                break;
            case "DELETED":
                to = superAdmin;
                cc = buildCc("", to, assetManager, auditor);
                break;
        }
        return new EmailRouting(to, cc);
    }

    public static EmailRouting buildMasterDataRecipients(String action) {
        String superAdmin = NotificationRecipientResolver.getPrimaryEmailByRole("SUPER_ADMIN");
        String assetManager = NotificationRecipientResolver.getPrimaryEmailByRole("ASSET_MANAGER");
        String auditor = NotificationRecipientResolver.getPrimaryEmailByRole("AUDITOR");
        
        String to = "";
        String cc = "";
        
        switch (action) {
            case "ADDED":
            case "UPDATED":
                to = assetManager;
                cc = buildCc("", to, superAdmin);
                break;
            case "DELETED":
                to = superAdmin;
                cc = buildCc("", to, assetManager, auditor);
                break;
        }
        return new EmailRouting(to, cc);
    }

    public static EmailRouting buildAssetRequestRecipients(String action, int employeeId) {
        String assetManager = NotificationRecipientResolver.getPrimaryEmailByRole("ASSET_MANAGER");
        String superAdmin = NotificationRecipientResolver.getPrimaryEmailByRole("SUPER_ADMIN");
        
        String employeeEmail = NotificationRecipientResolver.getEmployeeEmailByEmployeeId(employeeId);
        String deptHead = NotificationRecipientResolver.getDepartmentHeadEmailByEmployeeId(employeeId);
        if (deptHead.isEmpty()) deptHead = NotificationRecipientResolver.getPrimaryEmailByRole("DEPARTMENT_HEAD");
        
        String to = "";
        String cc = "";
        
        switch (action) {
            case "NEW":
                to = assetManager;
                cc = buildCc("", to, deptHead, employeeEmail);
                break;
            case "NEW_DEPT_HEAD":
                // Request just landed in PENDING_DEPT_HEAD - the Department
                // Head reviews first, so they're the primary recipient here
                // (not the Asset Manager, who has no action to take until the
                // request is forwarded).
                to = deptHead;
                cc = buildCc("", to, employeeEmail);
                break;
            case "FORWARDED":
                // Department Head forwarded the request on - it now sits at
                // PENDING for the Asset Manager, mirroring the "NEW" routing
                // for a request that started there directly.
                to = assetManager;
                cc = buildCc("", to, deptHead, employeeEmail);
                break;
            case "DEPT_HEAD_REJECTED":
                // Terminal rejection at the Department Head stage - the
                // request never reaches the Asset Manager, so they're left
                // out of this notice entirely.
                to = employeeEmail;
                cc = buildCc("", to, deptHead);
                break;
            case "ACK":
                to = employeeEmail;
                cc = "";
                break;
            case "APPROVED":
            case "REJECTED":
            case "FULFILLED":
                to = employeeEmail;
                cc = buildCc("", to, assetManager, deptHead);
                break;
            case "HIGH_VALUE":
                to = assetManager;
                cc = buildCc("", to, superAdmin, deptHead);
                break;
        }
        return new EmailRouting(to, cc);
    }

    public static EmailRouting buildAllocationRecipients(String action, int employeeId) {
        String assetManager = NotificationRecipientResolver.getPrimaryEmailByRole("ASSET_MANAGER");
        String employeeEmail = NotificationRecipientResolver.getEmployeeEmailByEmployeeId(employeeId);
        String deptHead = NotificationRecipientResolver.getDepartmentHeadEmailByEmployeeId(employeeId);
        if (deptHead.isEmpty()) deptHead = NotificationRecipientResolver.getPrimaryEmailByRole("DEPARTMENT_HEAD");
        
        String to = employeeEmail;
        String cc = buildCc("", to, assetManager, deptHead);
        
        return new EmailRouting(to, cc);
    }

    public static EmailRouting buildReturnRecipients(String action, int employeeId) {
        String assetManager = NotificationRecipientResolver.getPrimaryEmailByRole("ASSET_MANAGER");
        String superAdmin = NotificationRecipientResolver.getPrimaryEmailByRole("SUPER_ADMIN");
        String auditor = NotificationRecipientResolver.getPrimaryEmailByRole("AUDITOR");
        
        String employeeEmail = NotificationRecipientResolver.getEmployeeEmailByEmployeeId(employeeId);
        String deptHead = NotificationRecipientResolver.getDepartmentHeadEmailByEmployeeId(employeeId);
        if (deptHead.isEmpty()) deptHead = NotificationRecipientResolver.getPrimaryEmailByRole("DEPARTMENT_HEAD");
        
        String to = "";
        String cc = "";
        
        switch (action) {
            case "SUBMIT":
                to = assetManager;
                cc = buildCc("", to, deptHead);
                break;
            case "ACCEPTED":
                to = employeeEmail;
                cc = buildCc("", to, assetManager, deptHead);
                break;
            case "REJECTED":
                to = employeeEmail;
                cc = buildCc("", to, assetManager, deptHead, superAdmin);
                break;
            case "DAMAGED":
                to = assetManager;
                cc = buildCc("", to, superAdmin, auditor, deptHead);
                break;
        }
        return new EmailRouting(to, cc);
    }

    public static EmailRouting buildMaintenanceRecipients(String action, int assetId) {
        String assetManager = NotificationRecipientResolver.getPrimaryEmailByRole("ASSET_MANAGER");
        String superAdmin = NotificationRecipientResolver.getPrimaryEmailByRole("SUPER_ADMIN");
        String auditor = NotificationRecipientResolver.getPrimaryEmailByRole("AUDITOR");
        
        String deptHead = NotificationRecipientResolver.getDepartmentHeadEmailByAssetId(assetId);
        if (deptHead.isEmpty()) deptHead = NotificationRecipientResolver.getPrimaryEmailByRole("DEPARTMENT_HEAD");
        
        String to = "";
        String cc = "";
        
        switch (action) {
            case "NEW":
                to = assetManager;
                cc = buildCc("", to, superAdmin);
                break;
            case "SENT":
                to = assetManager;
                cc = buildCc("", to, superAdmin, deptHead);
                break;
            case "COMPLETED":
                to = assetManager;
                cc = buildCc("", to, deptHead);
                break;
            case "HIGH_COST":
                to = superAdmin;
                cc = buildCc("", to, assetManager, auditor, deptHead);
                break;
            case "OVERDUE":
                to = assetManager;
                cc = buildCc("", to, superAdmin);
                break;
        }
        return new EmailRouting(to, cc);
    }

    public static EmailRouting buildSettingsSecurityRecipients(String action, int affectedUserId) {
        String superAdmin = NotificationRecipientResolver.getPrimaryEmailByRole("SUPER_ADMIN");
        String auditor = NotificationRecipientResolver.getPrimaryEmailByRole("AUDITOR");
        String affectedUserEmail = NotificationRecipientResolver.getEmployeeEmailByUserId(affectedUserId);
        
        String to = "";
        String cc = "";
        
        switch (action) {
            case "SMTP_CHANGED":
            case "SETTINGS_UPDATE":
                to = superAdmin;
                cc = "";
                break;
            case "ROLE_CHANGED":
            case "ROLE_UPDATE":
                to = affectedUserEmail;
                cc = buildCc("", to, superAdmin);
                break;
            case "ADMIN_CHANGED":
                to = superAdmin;
                cc = buildCc("", to, auditor);
                break;
            case "PASSWORD_CHANGED":
            case "PASSWORD_CHANGE":
                to = affectedUserEmail;
                cc = "";
                break;
            case "BACKUP_RESTORE":
            case "BACKUP":
                to = superAdmin;
                cc = buildCc("", to, auditor);
                break;
        }
        return new EmailRouting(to, cc);
    }
}
