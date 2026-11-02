package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * CopilotKnowledgeBase — how IR-AMS actually works, in the model's own words
 * problem: everything CopilotToolExecutor answers is a live data lookup
 * (how many, who holds, show me); nothing answers "how does X work", "why
 * would a request go to my department head first", or "what happens when I
 * mark an asset damaged". A general-purpose model asked those questions
 * would reach for its own training knowledge of "how asset management
 * systems typically work" - which is exactly the wrong answer for a
 * CUSTOMIZED system whose real behavior (see every entry below) diverges
 * from the generic case in specific, load-bearing ways.
 *
 * Every entry here is grounded in an actual code read of this repository
 * (servlets/DAOs/schema.sql), not a general description of what an asset
 * management system "usually" does. Where the code's real behavior is
 * surprising, incomplete, or has a caveat (e.g. "Delete Employee" never
 * actually deletes anything; CANCELLED asset-request status exists in the
 * schema but no code path ever sets it), that caveat is stated plainly
 * rather than smoothed over - an honest "the CANCEL button doesn't exist
 * yet" beats a confident guess that it does.
 *
 * Deliberately a small, hand-curated set of substantial topics rather than
 * one entry per module: this is a comprehension aid for HOW THE SYSTEM
 * WORKS, meant to be searched by CopilotAgentLoop and read once per
 * relevant question - not a wiki update on every schema change moved into a
 * different file. If this drifts from the code, that is a real defect the
 * same way stale documentation always is; there is no automatic sync.
 */
public final class CopilotKnowledgeBase {

    private CopilotKnowledgeBase() {
    }

    public static final class Topic {
        public final String id;
        public final String title;
        public final List<String> keywords;
        public final String content;

        Topic(String id, String title, List<String> keywords, String content) {
            this.id = id;
            this.title = title;
            this.keywords = keywords;
            this.content = content;
        }
    }

    private static final List<Topic> TOPICS = new ArrayList<Topic>();

    private static void add(String id, String title, String content, String... keywords) {
        TOPICS.add(new Topic(id, title, Arrays.asList(keywords), content));
    }

    static {
        add("asset_request_lifecycle", "How an asset request moves from creation to fulfillment",
            "An asset request's status is one of PENDING_DEPT_HEAD, PENDING, APPROVED, REJECTED, "
            + "FULFILLED, or CANCELLED.\n\n"
            + "When an EMPLOYEE files their own request, it starts at PENDING_DEPT_HEAD only if their "
            + "department currently has an ACTIVE department head assigned - otherwise it goes straight "
            + "to PENDING (the Asset Manager's queue). When any operations role (Asset Manager, "
            + "Department Head, Admin, Super Admin) files a request on someone's behalf, it always goes "
            + "straight to PENDING, skipping the department-head stage entirely.\n\n"
            + "At PENDING_DEPT_HEAD, only the request's own department head (or Admin/Super Admin) can "
            + "act: Forward moves it to PENDING for the Asset Manager; Reject ends it at REJECTED "
            + "immediately - it never reaches the Asset Manager. Department Heads cannot give final "
            + "approval themselves, only forward or reject at their own stage.\n\n"
            + "At PENDING, the Asset Manager (or Admin/Super Admin) gives the final decision: APPROVED "
            + "or REJECTED. An APPROVED request can later be marked FULFILLED.\n\n"
            + "Two things worth knowing that are easy to assume otherwise: CANCELLED is a real status "
            + "in the system's design, but there is currently no button or action anywhere that actually "
            + "sets it - a request cannot currently be cancelled by anyone once filed. And marking a "
            + "request FULFILLED is just a status label the Asset Manager applies - it does not "
            + "automatically create or require an actual asset allocation; fulfilling a request and "
            + "allocating the asset are two separate manual steps today.",
            "asset request", "request status", "pending", "approve request", "reject request",
            "why department head review", "fulfilled", "cancel request", "workflow", "requisition");

        add("asset_status_lifecycle", "How an asset's status changes through its life",
            "An asset's status is one of AVAILABLE, ALLOCATED, UNDER_MAINTENANCE, DISPOSED, LOST, or "
            + "DAMAGED, and every transition happens as a side effect of a real action - never edited "
            + "directly.\n\n"
            + "AVAILABLE -> ALLOCATED happens when an asset is allocated to an employee (only possible "
            + "while it is genuinely AVAILABLE - the system locks the row to prevent two allocations "
            + "racing for the same asset).\n\n"
            + "ALLOCATED -> (AVAILABLE, DAMAGED, or UNDER_MAINTENANCE) happens on return, depending on "
            + "the condition it's returned in: returned GOOD makes it AVAILABLE again; returned DAMAGED "
            + "sets it to DAMAGED; returned needing repair sends it to UNDER_MAINTENANCE.\n\n"
            + "An asset can also move to/from UNDER_MAINTENANCE directly through a maintenance log "
            + "update, and back to AVAILABLE once maintenance is marked complete - but this is blocked "
            + "entirely if the asset has already been DISPOSED.\n\n"
            + "-> DISPOSED is one-way and final: disposal is refused if the asset is already disposed, "
            + "still has an active allocation, or already has a disposal record. Once disposed, the "
            + "asset's record and full history (allocations, returns, maintenance) are permanently kept "
            + "for audit purposes - disposal is the ONLY way an asset ever leaves active service in this "
            + "system; there is no hard-delete for assets anywhere.\n\n"
            + "LOST exists as a valid status and as a disposal reason, but no button or workflow in the "
            + "current system actually sets an asset to LOST directly - treat that as a status the data "
            + "model supports rather than one you can currently trigger through the UI.",
            "asset status", "available", "allocated", "disposed", "damaged", "lost", "asset lifecycle",
            "dispose asset", "disposal", "mark damaged", "under maintenance");

        add("employee_lifecycle", "How an employee record moves from hire to departure",
            "A new employee is created as ACTIVE. Moving them to a different department only changes "
            + "their department - it does not touch their active/inactive status, so a transferred "
            + "employee stays fully active and can still be allocated new assets right away.\n\n"
            + "Disabling an employee sets them to INACTIVE - a reversible, day-to-day action (e.g. "
            + "someone on long leave). Retiring an employee is a separate, distinct terminal action that "
            + "requires every asset currently allocated to them to be returned as part of the same step - "
            + "there is no way to retire someone while they still hold allocated assets.\n\n"
            + "Deleting an employee is blocked unless three conditions all hold: they are already "
            + "deactivated (not still ACTIVE), they have no currently-allocated assets, and they have no "
            + "PENDING or APPROVED asset requests outstanding. Worth knowing plainly: despite being "
            + "called 'delete', this action never actually removes the employee record or hard-deletes "
            + "anything - it only re-confirms the employee is INACTIVE. The employee's row, and their "
            + "full allocation/return/audit history, always remains in the system permanently, the same "
            + "way assets are never hard-deleted either.\n\n"
            + "A Department Head can only disable/retire/delete employees confirmed to be in their own "
            + "department; Admin and Super Admin can do so for anyone.",
            "employee status", "disable employee", "delete employee", "retire employee",
            "employee lifecycle", "deactivate", "employee department transfer");

        add("qr_control_center", "How QR codes, scanning, and physical tagging work",
            "Each asset can have a unique QR token generated for it (Asset Manager/Admin/Super Admin "
            + "only) - a random code that resolves to a public scan page, with no login required to view "
            + "it. Generating a NEW token for an asset that already has one (re-issuing) keeps a record "
            + "of the old and new token so history isn't lost.\n\n"
            + "Scanning a QR code opens a public page that looks the asset up (by its token) and logs "
            + "every scan attempt - whether it found a real asset or the token was invalid - so the scan "
            + "log can show both legitimate lookups and invalid/tampered attempts.\n\n"
            + "QR 'tagging status' is tracked separately from the digital token itself, because "
            + "generating a QR code digitally and physically printing + sticking the label onto the "
            + "asset are two different steps: a print status (not yet printed / printed / needs "
            + "reprinting) and a tag status (not yet tagged / tagged onto the asset / tag damaged / tag "
            + "removed). 'QR tagging pending' specifically means a QR code exists digitally for the "
            + "asset but the physical label hasn't been printed and/or physically attached yet.\n\n"
            + "Viewing the QR Control Center is available to Asset Manager/Admin/Super Admin/Auditor; "
            + "generating, re-issuing, or updating tagging status is Asset Manager/Admin/Super Admin only.",
            "qr code", "qr control center", "qr tagging", "qr scan", "generate qr", "reissue qr",
            "qr token", "scan logs", "invalid token");

        add("physical_verification", "How physical asset verification (stock-checking) works",
            "This is the process of physically confirming assets are where the records say they are. "
            + "An Asset Manager/Admin/Super Admin schedules a verification duty, assigning a specific "
            + "officer to check a set of assets within a date range - an officer can't be double-booked "
            + "with two overlapping active duties for the same round.\n\n"
            + "The assigned officer then submits, per asset, what they actually found: verified and "
            + "matches records, wrong location, wrong holder, not found at all, damaged, under repair, "
            + "or needs further review. Submitting this immediately updates the asset's own condition: "
            + "a verified-good asset is marked serviceable; damaged or repair-flagged assets are flagged "
            + "as needing attention (an under-repair finding also moves the asset itself into "
            + "UNDER_MAINTENANCE status); anything not found, in the wrong place, or with the wrong "
            + "holder is flagged as needing attention pending investigation. Every submission stamps "
            + "the asset's last-verified date to today, regardless of outcome.\n\n"
            + "Once a batch of verifications is submitted, an Asset Manager/Admin/Super Admin reviews "
            + "and approves or rejects it - a verification a submitting officer entered cannot be acted "
            + "on twice, and once approved/rejected it is locked from further edits.\n\n"
            + "Department Heads and Auditors can view verification records and reports, but only Asset "
            + "Manager/Admin/Super Admin can schedule duties, submit findings, or review/approve them.",
            "physical verification", "stock check", "verification duty", "audit assets",
            "verify assets", "verification round", "asset condition check");

        add("rbac_roles", "What each user role can actually do in IR-AMS",
            "IR-AMS has six roles: SUPER_ADMIN, ADMIN, ASSET_MANAGER, AUDITOR, DEPARTMENT_HEAD, and "
            + "EMPLOYEE. Access is checked on every single page/action (default-deny - a role must be "
            + "explicitly permitted, not just 'not explicitly blocked').\n\n"
            + "SUPER_ADMIN and ADMIN have full administrative reach - system settings, user/role "
            + "management, backups, and (for Super Admin specifically) emergency account-recovery tools "
            + "no other role can see.\n\n"
            + "ASSET_MANAGER is the day-to-day operations role: creating/editing/disposing assets, "
            + "processing allocations and returns, logging maintenance, managing categories/vendors, "
            + "generating QR codes, and scheduling/submitting/reviewing physical verification.\n\n"
            + "AUDITOR is read-only oversight across assets, employees, maintenance, QR activity, "
            + "reports, and the audit trail itself - no role in this system has fewer write permissions "
            + "than Auditor.\n\n"
            + "DEPARTMENT_HEAD manages their own department's employees (add, edit, disable, retire, "
            + "transfer - all scoped to people actually in their department) and reviews the "
            + "department-head stage of asset requests from their team, but does NOT give final approval "
            + "on a request - that decision belongs to the Asset Manager.\n\n"
            + "EMPLOYEE is self-service only: file their own asset requests (routed through their "
            + "department head first, if their department has one), view their own assets/requests/"
            + "returns, submit their own maintenance requests, and return assets allocated to them. An "
            + "employee has no visibility into or authority over anyone else's records.",
            "role", "roles", "rbac", "permissions", "who can", "access control", "super admin",
            "asset manager role", "auditor role", "what can a department head do",
            "department head role", "employee role");

        add("warranty_tracking", "How warranty tracking and renewal works",
            "Every asset has a single warranty expiry date. Renewing a warranty - either to a specific "
            + "new date or by extending a number of months from the current expiry (1 to 240 months, no "
            + "backdating into the past) - updates that date and keeps a full history of every past "
            + "renewal (previous expiry, new expiry, cost, who did it) so nothing is overwritten "
            + "silently. Renewing is limited to Asset Manager/Admin/Super Admin; viewing renewal history "
            + "additionally allows Auditor, and the warranty report itself is visible to anyone logged "
            + "in (the Renew button is what's actually restricted).\n\n"
            + "A background check runs once a day and emails the Asset Manager (cc Super Admin) about "
            + "assets whose warranty is expiring within a configurable number of days (30 by default). "
            + "It won't re-email about the same asset every single day it stays inside that window - "
            + "once alerted, that asset is skipped again until the alert would naturally be needed "
            + "afresh. This only runs at all if email alerts are enabled in Settings.",
            "warranty", "warranty expiry", "renew warranty", "warranty alert", "warranty renewal",
            "warranty history", "expiring warranty");

        add("asset_health_score", "How the Asset Health Score is calculated",
            "Every asset gets a health score from 0-100, calculated fresh each time the Asset Health "
            + "page is viewed (it is not a stored value that updates in the background). It starts at "
            + "100 and loses points for: being under maintenance or damaged; poor condition; a "
            + "concerning service status (scrap-recommended is the heaviest penalty); an expired or "
            + "soon-expiring warranty; a high number of past maintenance records; high cumulative "
            + "maintenance cost; being older than roughly 4-7 years; and not having been physically "
            + "verified in over a year. A disposed or lost asset always scores 0. The resulting score "
            + "maps to a plain recommendation: 85+ keep using it, 70+ schedule maintenance, 45+ repair "
            + "recommended, below that replace soon or a dispose candidate.\n\n"
            + "Settings > Operations > Asset Health has a scoring on/off toggle and five weight sliders "
            + "(age/maintenance/warranty/condition/verification), and both are genuinely live: the "
            + "toggle fully disables the whole Asset Health page (it shows a clear \"disabled in "
            + "Settings\" notice instead of scores) when switched off, and each slider scales its "
            + "matching category of penalty proportionally to how far it's moved from its default value "
            + "- e.g. doubling the Condition weight roughly doubles every condition-related penalty. "
            + "Leaving every slider at its default reproduces the same scoring as before these controls "
            + "existed.\n\n"
            + "Visible to Super Admin, Admin, Asset Manager, Department Head, and Auditor.",
            "asset health", "health score", "asset condition score", "health settings",
            "replace asset", "dispose candidate");

        add("vendor_category_management", "How vendors, categories, and category-vendor mapping work",
            "A vendor can only supply asset categories it has been explicitly and ACTIVELY mapped to - "
            + "this is enforced at the point of creating or editing an asset, not just a suggestion in "
            + "the UI: if you try to create or edit an asset with a category+vendor combination that "
            + "isn't an active mapping, the save is refused outright. Deactivating a mapping only blocks "
            + "new assets going forward - it does not retroactively change any asset that already used "
            + "that vendor for that category. Managing vendors and category-vendor mappings is limited "
            + "to Super Admin, Admin, and Asset Manager.",
            "vendor", "supplier", "category vendor mapping", "category mapping", "add vendor",
            "which vendor supplies");

        add("backup_restore", "How database backup and restore actually work",
            "Backup produces a complete SQL dump of the entire database - every table, structure and "
            + "data - as a single downloadable .sql file, triggered manually by Super Admin or Admin. "
            + "Restore uploads a .sql file and requires typing an exact confirmation phrase before it "
            + "will run, as a deliberate safeguard against an accidental restore. Before touching "
            + "anything, restore automatically takes its own safety backup first and will refuse to "
            + "proceed at all if that safety backup fails - so a restore attempt can never leave you "
            + "without a way back. Every backup and restore is logged to the audit trail.\n\n"
            + "Settings > Operations > Backup's \"Auto Backup Schedule\" (Never/Daily/Weekly/Monthly) and "
            + "\"Backup Location\" are both live in the system today: a background scheduler checks once "
            + "a day whether a scheduled backup is due, and if so automatically writes a full dump to "
            + "the configured location, using the exact same dump logic as a manual backup - so yes, the "
            + "system does take automatic scheduled backups once this is configured, not only manual "
            + "ones. A missed check (e.g. the server was down) is not lost - the next check still catches "
            + "it as overdue. Manual backup via the Backup & Restore page still works independently at "
            + "any time.",
            "backup", "restore database", "backup schedule", "database dump", "auto backup",
            "automatic backup", "scheduled backup", "does the system backup automatically");

        add("global_search", "How the global search bar works and what it can surface",
            "The global search bar looks across assets, employees, vendors, categories, locations, "
            + "maintenance logs, asset requests, allocations, returns, physical verification, disposal "
            + "records, and audit logs in one search. Role-scoping is applied consistently for the more "
            + "sensitive areas - asset and employee results, physical verification, disposal, and audit "
            + "logs only appear for roles that could open those pages directly (an Employee never sees "
            + "these). For a handful of the less sensitive categories - vendors, categories, locations, "
            + "maintenance logs, and asset requests/allocations/returns - search currently does not "
            + "apply that same role filter, so results from those areas can surface for any logged-in "
            + "user, including roles that could not open the equivalent list page on its own. If exact "
            + "per-role search visibility ever matters for something sensitive, verify it directly "
            + "rather than assuming search matches that page's own access level.",
            "global search", "search bar", "search assets", "search everything");

        add("reports_and_audit", "What reports exist, and what the audit trail actually captures",
            "The Reports module offers dedicated reports for warranty, assets, employees, maintenance, "
            + "allocations, returns, requests, disposal, physical verification, and QR (register/scan "
            + "logs/coverage), each exportable as an Excel (.xlsx) file - there is no PDF export "
            + "anywhere in the system. Reports are visible to Super Admin, Admin, Asset Manager, "
            + "Department Head, and Auditor.\n\n"
            + "The audit trail records who did what, when, from where, and records action details in "
            + "plain text - it covers the great majority of real actions across the app (assets, "
            + "allocations, returns, maintenance, employees, departments, vendors, categories, warranty "
            + "renewals, backup/restore, settings changes, logins, password resets, role assignment, "
            + "document uploads, and every Copilot write command). It is not fully universal, though: a "
            + "small number of specific actions - processing a return through the dedicated return-"
            + "allocation action, updating QR tagging status, and changing a user's role - do not "
            + "currently write an audit log entry, so don't assume every single mutating action in the "
            + "app is guaranteed to appear in the audit trail. Viewing the audit trail itself is limited "
            + "to Super Admin, Admin, and Auditor.",
            "reports", "export report", "excel export", "audit log", "audit trail", "who did this",
            "action history");

        add("role_duty_assignment", "How Role & Duty Assignment actually works",
            "Despite the name, this module assigns the same six system roles (Super Admin, Admin, Asset "
            + "Manager, Auditor, Department Head, Employee) - it is not a separate, more granular set of "
            + "job titles. A \"duty\" assignment is really that role plus an optional free-text "
            + "designation and, for Department Head specifically, a required department.\n\n"
            + "Only Admin and Department Head can assign roles/duties - a Department Head can only do so "
            + "for employees already in their own department, and can never touch Super Admin. Assigning "
            + "someone a new elevated role automatically deactivates their previous one; Admin is treated "
            + "as a single managed seat (promoting someone new to Admin deactivates whoever held it "
            + "before); and the system will not let you deactivate the very last active Admin or Super "
            + "Admin, to prevent locking everyone out. Assigning or removing someone's Department Head "
            + "duty automatically keeps that department's recorded head in sync.",
            "role assignment", "duty assignment", "assign role", "who can assign roles",
            "department head duty", "promote to admin");

        add("departments_management", "How departments are created, headed, and (not) deleted",
            "Creating, editing, or deleting a department is limited to Super Admin/Admin; everyone can "
            + "view the department list, and every role except Employee can export it. A department "
            + "head is optional - a department can exist with no head assigned at all - and the "
            + "recorded head can be set directly when editing the department, or kept automatically in "
            + "sync through the Role & Duty Assignment module.\n\n"
            + "A department can only actually be deleted if it is completely empty - no assets, no "
            + "employees, no role assignments, no asset-request history, and no linked locations. In "
            + "practice this means a real, populated department cannot be deleted. The available "
            + "alternative is disabling it (marking it inactive), which is purely a status flag - it "
            + "does not move, unassign, or otherwise affect any employees or assets still linked to it.",
            "department", "delete department", "department head", "disable department",
            "create department");

        add("categories_management", "How asset categories are managed",
            "Categories can be created and edited by Super Admin, Admin, or Asset Manager. There is no "
            + "delete function for a category at all - even at the database level it is structurally "
            + "protected so a category referenced by any asset or asset request cannot be removed. The "
            + "only lifecycle action available is enabling or disabling a category, which is just a "
            + "status flag - it does not reassign or otherwise touch any assets already using that "
            + "category.",
            "category", "asset category", "delete category", "disable category", "create category");

        add("document_uploads", "Rules for uploading documents to assets, employees, and vendors",
            "Assets and vendors accept documents up to 10MB (PDF, images, Word, Excel, or CSV); "
            + "employees are capped at 5MB and don't accept spreadsheet files. Every upload is checked "
            + "against an allowed-extension whitelist, and the file's stored type is determined "
            + "server-side from that validated extension rather than trusted from whatever the browser "
            + "claims - a deliberate anti-spoofing measure.\n\n"
            + "Uploading is limited to Super Admin/Admin/Asset Manager for assets and vendors, and to "
            + "Super Admin/Admin or that employee's own Department Head for employee documents. Viewing/"
            + "downloading is a bit wider - Auditor can view documents on all three, and Department Head "
            + "can view documents for employees in their own department.\n\n"
            + "Worth knowing plainly: documents are NOT versioned. Uploading a new document of the same "
            + "type does not replace or overwrite the previous one - every upload is kept as its own "
            + "separate record, so multiple documents of the same type simply accumulate over time.",
            "upload document", "document upload", "file size limit", "attach document",
            "vendor document", "employee document", "asset document");

        add("notification_system", "How the notification/alert toggles in Settings relate to each other",
            "Email Alerts is a master switch: if it's off, no automated email goes out for ANY module, "
            + "no matter what the other individual toggles say. If Email Alerts is on, each module has "
            + "its own toggle that further controls it specifically: Asset Requests, Returns, "
            + "Maintenance, Audit/Security, Warranty Expiry, and the Copilot's daily digest all have "
            + "their own on/off switch. Disposal notifications are always sent regardless of any toggle. "
            + "Configuring any of this is limited to Super Admin/Admin.\n\n"
            + "The \"Dashboard Alerts\" toggle (Settings > Notifications) is separate from the Email "
            + "Alerts master switch above - it controls only the \"Action Required: Overdue Items\" panel "
            + "on the main Dashboard (inspections due, maintenance overdue, warranties expiring), not any "
            + "email. Turning it off hides that panel entirely even when there are genuinely overdue "
            + "items; it defaults to on.",
            "notification settings", "email alerts", "alert toggle", "disable notifications",
            "dashboard alerts");

        add("settings_overview", "What's in the Settings page and who can change it",
            "The entire Settings page - every tab - is restricted to Super Admin and Admin only; no "
            + "other role can open it at all. The tabs cover: Organization profile, Email/SMTP "
            + "configuration, QR & Mobile settings, AI Copilot (provider, credentials, fallback "
            + "behavior), Notifications (the alert toggles), Security, Operations (Asset Health Score, "
            + "upload limits, backup settings), and System Info. There's no finer-grained permission "
            + "within Settings itself - if a role can open the page at all, it can see and change every "
            + "tab on it.",
            "settings", "settings page", "who can change settings", "configuration");

        add("maintenance_workflow", "How maintenance logs and maintenance requests actually work",
            "There are two separate tracks that are easy to confuse. Maintenance LOGS (the ones "
            + "created via \"Add Maintenance\"/\"Schedule Service\") can only be created directly by "
            + "Super Admin, Admin, or Asset Manager - there is no employee-initiated path into a "
            + "maintenance log. Maintenance REQUESTS are the opposite: only an Employee can file one, "
            + "and only for an asset currently allocated to them; Super Admin/Admin/Asset Manager then "
            + "review it (Pending, Approved, Rejected, In Progress, Completed). Approving a request does "
            + "NOT automatically create a maintenance log - an admin still has to separately run \"Add "
            + "Maintenance\" to actually record the work. Resolving a maintenance record marks the asset "
            + "back to Available, unless it still has an active allocation, in which case it correctly "
            + "goes to Allocated instead. A disposed asset can never have maintenance added, edited, or "
            + "resolved. Maintenance history/view pages are also open to Auditor, even though Auditor "
            + "cannot create or resolve maintenance.",
            "maintenance request", "add maintenance", "resolve maintenance", "schedule service",
            "maintenance log", "who can approve maintenance");

        add("asset_disposal", "How asset disposal actually works, and why it's final",
            "Disposal is restricted to Super Admin, Admin, and Asset Manager. Before it's allowed, the "
            + "system checks the disposal date isn't in the future or before the asset's own purchase "
            + "date, requires a reason and a non-negative disposal value, and - critically - refuses if "
            + "the asset still has an active allocation (it must be returned first) or already has a "
            + "disposal record. On success the asset is permanently flagged Disposed, its condition is "
            + "set to Damaged, and its service status to Scrap Recommended, all in one transaction.\n\n"
            + "There is no undo. No screen or Copilot action can reactivate a disposed asset. Its past "
            + "warranty and maintenance history rows are left in place, not deleted, but every part of "
            + "the system that could otherwise modify a disposed asset (adding/editing maintenance, "
            + "resolving it, etc.) explicitly refuses to touch a disposed asset from that point on - so "
            + "that history becomes permanently frozen, not just harder to find.",
            "dispose asset", "disposal", "scrap asset", "asset disposal", "undo disposal",
            "can you un-dispose");

        add("employee_transfer", "How transferring an employee between departments works",
            "Only Super Admin, Admin, or a Department Head can actually transfer an employee - and a "
            + "Department Head can only transfer employees within their own department. An employee "
            + "cannot transfer themselves; the closest they can do is submit a non-binding \"keep this "
            + "asset\" or \"return this asset\" preference per allocated asset, which never changes their "
            + "department or allocation on its own - it's only a suggestion an admin still has to act on "
            + "when actually running the transfer.\n\n"
            + "During a real transfer, each currently-allocated asset is individually either retained "
            + "(travels with the employee to the new department, allocation record untouched) or "
            + "returned (goes through the normal return process). If any requested return fails partway "
            + "through, the whole transfer is aborted and the employee's department is not changed - "
            + "already-completed retains/returns from that same attempt are not rolled back, so it's "
            + "safe to simply retry. The employee's own status always stays Active; a transfer never "
            + "changes it.",
            "transfer employee", "change department", "employee transfer", "department transfer",
            "transfer preference");

        add("password_reset_recovery", "How password reset, password change, and account recovery differ",
            "Three genuinely different mechanisms exist, easy to conflate. \"Forgot Password\" is a "
            + "self-service, email-token-based reset: it always shows the same \"check your email\" "
            + "message whether or not the account actually exists, specifically so no one can use it to "
            + "discover which emails are registered; the reset link only ever goes to the email already "
            + "on file, is capped at 3 requests per 15 minutes per account, and expires after 30 minutes. "
            + "\"Change Password\" is the in-session version - it requires knowing your current password "
            + "and won't accept the same password again.\n\n"
            + "\"Emergency Recovery\", despite the name, is NOT a password tool at all and cannot reset "
            + "anyone's password. It's restricted to Super Admin only, requires re-entering the Super "
            + "Admin's own password first, and exists purely to recover from an ADMIN account being "
            + "locked out - it reassigns who holds the single ADMIN seat to a different user. It "
            + "explicitly refuses to touch or reassign the Super Admin role itself.",
            "forgot password", "reset password", "change password", "emergency recovery",
            "locked out", "account recovery");

        add("role_assignment_vs_role_editing", "Role & Duty Assignment vs. what actually changes a login's permissions",
            "This is one of the most important distinctions to get right in IR-AMS: the \"Role & Duty "
            + "Assignment\" page in the sidebar (open to Admin and Department Head) only writes to a "
            + "duty-assignment record - plus syncing an employee's designation and who is marked as a "
            + "department's head - it does NOT change what that person's account is actually authorized "
            + "to do when they log in.\n\n"
            + "The account's real, enforced permission level (what login and every access check actually "
            + "reads) is only ever changed by a separate \"Manage Roles\" screen, restricted to Super "
            + "Admin/Admin - and that screen is not linked anywhere in the normal menus; it's only "
            + "reachable by navigating to its URL directly. So assigning someone a \"duty\" through the "
            + "visible sidebar page alone will NOT change what they can access - if the goal is to "
            + "actually change a login's real permission level (SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR/"
            + "DEPARTMENT_HEAD/EMPLOYEE), that has to go through Manage Roles specifically, not Role & "
            + "Duty Assignment. There's also a separate read-only Access Matrix reference page showing "
            + "what each role can do - but it's a hand-written table maintained independently of the "
            + "actual permission-checking code, so treat it as a helpful reference rather than a "
            + "guaranteed-accurate source if the two ever disagree.",
            "role assignment", "duty assignment", "manage roles", "access matrix", "change role",
            "who has admin access", "role vs duty");

        add("currency_settings", "What the Currency setting in Settings actually affects",
            "Settings lets Super Admin/Admin choose a currency code (INR/USD/EUR/GBP) and a timezone. "
            + "It's worth knowing this is cosmetic and narrow, not a system-wide switch: the stored "
            + "currency value is only ever read back on the Settings/profile screens themselves. Every "
            + "actual money display elsewhere in the system - reports, exports, disposal and maintenance "
            + "notification emails, the employee and asset lists - shows amounts with a fixed \"Rs.\" "
            + "label regardless of what's chosen here. So changing this setting does not change how "
            + "costs, values, or prices are displayed anywhere else in the application.",
            "currency", "currency settings", "change currency", "timezone setting");

        add("alert_center_overdue_actions", "How Alert Center and Overdue Actions differ from the Dashboard's own alert panel",
            "ONLY-ON-OVERDUE-ACTIONS, not on the Dashboard panel: OVERDUE RETURNS (assets still "
            + "allocated to someone past their expected return date). That is the single, complete "
            + "answer to \"what does Overdue Actions show that the Dashboard panel doesn't\" - nothing "
            + "else on Overdue Actions is exclusive to it.\n"
            + "ONLY-ON-DASHBOARD-PANEL, not on Overdue Actions: INSPECTIONS DUE. That is the single, "
            + "complete answer to \"what does the Dashboard panel show that Overdue Actions doesn't\".\n"
            + "ON BOTH, not exclusive to either one: maintenance overdue, and warranties expiring "
            + "within 30 days.\n\n"
            + "Full picture, three different \"what needs attention\" views: the Dashboard's \"Action "
            + "Required\" panel covers exactly three things - inspections due, maintenance overdue, and "
            + "warranties expiring within 30 days - and can be switched off entirely by the Dashboard "
            + "Alerts toggle. \"Overdue Actions\" is a dedicated page with the same maintenance-overdue "
            + "and warranty-expiring items, but replaces \"inspections due\" with \"overdue returns\" "
            + "instead - it does not show inspections due at all. \"Alert Center\" is the broadest of "
            + "the three, adding physical verification issues, assets under maintenance or damaged, and "
            + "pending asset requests - and, for Super Admin/Admin/Asset Manager/Auditor only, two more "
            + "admin-only signals: pending disposal approvals and recent audit activity. Neither Alert "
            + "Center nor Overdue Actions requires any special role beyond being logged in - any role, "
            + "including Employee, can open both (Employee just won't see the two admin-only Alert "
            + "Center signals).",
            "alert center", "overdue actions", "overdue returns", "what needs attention",
            "action required");

        add("qr_reporting_and_reissue", "Reissuing a QR vs refreshing its URL, and what each QR report actually shows",
            "This is the one QR distinction most worth getting right: REISSUING a QR generates a brand "
            + "new token and immediately invalidates the old one - once reissued, the OLD printed QR code "
            + "stops working entirely and scanning it will log as an invalid-token attempt, so a physical "
            + "reprint is required afterward. REFRESHING THE URL is different and much less disruptive: it "
            + "only updates the stored web address text (e.g. after moving from a test link to the real "
            + "domain) without touching the underlying token - old printed QR codes KEEP WORKING after a "
            + "URL refresh, because scanning still resolves by the same unchanged token. Both actions are "
            + "restricted to Super Admin/Admin/Asset Manager (not Auditor, who can view every QR report but "
            + "not reissue or refresh).\n\n"
            + "Among the QR reports: Coverage Report is an aggregate percentage view (how much of the fleet "
            + "has a QR at all, by department/category); Missing QR Report is the actual row-level list of "
            + "which specific assets lack one; Exception Report is a combined register of three distinct "
            + "problems - a missing token, a stored QR that no longer matches the live URL, and a scan "
            + "attempt that hit an invalid/dead token; Scan Analytics covers usage patterns (trends, most-"
            + "scanned assets); IP Audit Report is a security-focused view of the same scan data, looking "
            + "at which IPs are doing the scanning; and Tagging Status tracks the separate physical "
            + "label-printing workflow, independent of whether a digital QR token even exists yet.",
            "qr reissue", "reissue qr", "refresh qr url", "qr exception report", "qr coverage",
            "missing qr", "scan analytics", "old qr code still work");

        add("analytics_vs_reports", "How the Analytics page differs from the Reports page",
            "These are genuinely different, not two names for the same screen. Analytics is a single-"
            + "screen KPI dashboard - key figures, operational ratios (utilization, maintenance load, "
            + "return rate, and a derived overall System Health label), and one chart of asset-status "
            + "distribution - with no export links or row-level data. Reports is primarily an Excel-export "
            + "hub (12 different exportable reports covering assets, employees, maintenance, requests, "
            + "disposal, warranty, verification, QR and audit data) plus a few live summary panels; a "
            + "Department Head can open the page and see those summary panels, but the export links "
            + "themselves are hidden from that role specifically, replaced with a restricted-access "
            + "notice.\n\n"
            + "Both pages are visible to Super Admin, Admin, Asset Manager, Department Head, and Auditor. "
            + "Worth knowing plainly: Analytics and the Dashboard both scope their figures down to a "
            + "Department Head's own department, but the Reports page's summary panels do not apply that "
            + "same department scoping anywhere - a Department Head viewing Reports sees organization-wide "
            + "totals in those panels, not their own department's numbers, which is inconsistent with what "
            + "the same role sees on Analytics or the Dashboard for the same kind of figures.",
            "analytics", "reports page", "analytics vs reports", "export reports", "excel export",
            "department head reports");

        add("public_qr_scan_exposure", "What a public, anonymous QR code scan actually reveals about an asset",
            "Scanning an asset's QR code needs no login at all - by design, anyone with the physical tag "
            + "can open the public asset view. Worth knowing plainly, since it is easy to assume "
            + "otherwise: a successful scan DOES show the asset's current holder - their real full name, "
            + "employee code, job designation, and the date they received the asset - to whoever scanned "
            + "it, with no authentication. Warranty, serial number, model number, and vendor/supplier are "
            + "NOT shown on a public scan. This is a confirmed, deliberate design choice, not an "
            + "oversight: the current-holder visibility is an intentional physical-asset-accountability "
            + "pattern (an \"if found, return to X\" model), kept as-is on purpose even though a separate "
            + "internal lookup path elsewhere in the same code goes out of its way to blank those same "
            + "holder fields for a different case - the two are not in conflict once you know the "
            + "holder-visible behavior is the confirmed, intended outcome.",
            "public qr scan", "anonymous qr", "who can scan qr", "qr privacy", "does qr show holder",
            "public asset view");

        add("copilot_capabilities", "What the AMS Copilot itself can and cannot do",
            "The Copilot can answer live data questions (counts, lists, who holds what, costs, "
            + "warranties, pending items), explain how any part of IR-AMS works, and carry out a small "
            + "set of real actions when explicitly asked and confirmed: allocate an asset, process a "
            + "return, approve or reject an asset request, and file a maintenance request. Every one of "
            + "those actions requires an explicit confirmation step before it runs, is checked against "
            + "the same role permissions as the equivalent screen in the app, and is logged in the audit "
            + "trail exactly like a manual action would be.\n\n"
            + "The Copilot deliberately does NOT create, edit, or delete assets or employees through "
            + "natural language, even though it could technically attempt to - those actions stay "
            + "restricted to their dedicated screens on purpose, because a misunderstood instruction for "
            + "an irreversible action is a much bigger problem than a misunderstood data question.\n\n"
            + "The Copilot can also see one attached photo per message - useful for reading an asset tag, "
            + "QR code, nameplate, or documenting visible damage - and it will look up real data using "
            + "anything legible in the photo rather than just describing the image.\n\n"
            + "The Copilot only knows about IR-AMS itself: its data, its modules, and how they work. It "
            + "is not a general-purpose assistant - questions unrelated to this system (general "
            + "knowledge, unrelated coding help, other products) are outside what it's here to do.",
            "copilot capabilities", "what can you do", "what can the copilot do", "copilot limitations",
            "can the copilot", "copilot actions", "ai assistant");
    }

    /**
     * Question words and other high-frequency filler that would otherwise
     * match trivially against keyword PHRASES like "what can you do" -
     * found by test, not by inspection: "what can a department head do"
     * scored higher against copilot_capabilities' "what can you do"
     * keyword (three throwaway-word hits: what/can/do) than against
     * rbac_roles' actual "department"/"head" content match, and a fully
     * unrelated query ("what is the capital of france...") matched three
     * topics purely on stopword overlap with their keyword phrases. Every
     * word here is either a question word, an auxiliary/copula verb, or a
     * preposition/article/conjunction generic enough to appear in nearly
     * any English sentence regardless of topic.
     */
    private static final java.util.Set<String> STOPWORDS = new java.util.HashSet<String>(Arrays.asList(
            "what", "why", "who", "when", "where", "which", "how",
            "does", "do", "did", "done", "doing",
            "is", "are", "was", "were", "be", "been", "being",
            "can", "could", "would", "should", "will", "shall", "may", "might",
            "the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "for",
            "with", "about", "into", "your", "you", "this", "that", "these", "those"
    ));

    /**
     * Ranks topics by keyword overlap with the query - deliberately not a
     * vector/embedding search (no embedding infrastructure exists in this
     * codebase, and at a handful of curated topics a semantic index would
     * add real complexity for no measurable improvement over plain keyword
     * matching once stopwords are excluded). Keyword-phrase hits count
     * triple a title/content word hit, since keywords are hand-picked to be
     * the phrases a real question would use - but only for words that
     * actually carry topic meaning; see STOPWORDS above for why that
     * exclusion is load-bearing, not just tidiness.
     */
    public static List<Topic> search(String query) {
        java.util.Set<String> queryWords = new java.util.LinkedHashSet<String>();
        for (String w : normalize(query).split("\\s+")) {
            if (w.length() >= 3 && !STOPWORDS.contains(w)) {
                queryWords.add(w);
            }
        }
        if (queryWords.isEmpty()) {
            return new ArrayList<Topic>();
        }

        List<Topic> ranked = new ArrayList<Topic>();
        Map<Topic, Integer> scores = new LinkedHashMap<Topic, Integer>();

        for (Topic topic : TOPICS) {
            int score = 0;
            String haystack = normalize(topic.title + " " + topic.content);

            // Weak signal: this query word appears somewhere in the topic's
            // prose, or in at least one keyword phrase (counted once per
            // query word regardless of how many keyword phrases happen to
            // contain it - two overlapping phrases sharing a word, e.g.
            // "dept head" and "department head" both containing "head",
            // must not double-count and out-rank a topic that only
            // mentions the word once; found by test).
            for (String word : queryWords) {
                if (haystack.contains(word)) {
                    score += 1;
                }
                for (String keyword : topic.keywords) {
                    if (normalize(keyword).contains(word)) {
                        score += 3;
                        break;
                    }
                }
            }

            // Strong signal: a whole keyword PHRASE is substantially
            // covered by the query's own words - e.g. the query "what can a
            // department head do" almost verbatim matches the keyword
            // phrase "what can a department head do" once stopwords are
            // stripped from both sides. This is what actually separates two
            // topics that merely share a couple of individual words
            // (found by test: word-level scoring alone tied rbac_roles and
            // asset_request_lifecycle on a department-head question, since
            // both mention "department"/"head" - only a real, near-complete
            // phrase match should decide a tie like that).
            //
            // Takes the BEST-covered keyword phrase, not the sum across all
            // of a topic's keywords - found by test, the hard way: summing
            // let a topic with many keyword phrases that all happen to
            // share one word (e.g. warranty_tracking's seven "warranty ..."
            // phrases, or departments_management's five "... department"
            // phrases) rack up a phrase-coverage score no single strong
            // match could ever produce, out-ranking a topic with fewer but
            // more precisely matching keywords purely because it listed
            // more variations. This scales correctly as more topics (and
            // more keywords per topic) are added; summing does not.
            int bestPhraseScore = 0;
            for (String keyword : topic.keywords) {
                String[] keywordWords = normalize(keyword).split("\\s+");
                int meaningful = 0;
                int covered = 0;
                for (String kw : keywordWords) {
                    if (kw.length() < 3 || STOPWORDS.contains(kw)) continue;
                    meaningful++;
                    if (queryWords.contains(kw)) covered++;
                }
                if (meaningful > 0) {
                    bestPhraseScore = Math.max(bestPhraseScore, (covered * 6) / meaningful);
                }
            }
            score += bestPhraseScore;

            if (score > 0) {
                scores.put(topic, score);
            }
        }

        scores.entrySet().stream()
                .sorted((a, b) -> b.getValue() - a.getValue())
                .limit(3)
                .forEach(e -> ranked.add(e.getKey()));
        return ranked;
    }

    private static String normalize(String text) {
        return text == null ? "" : text.toLowerCase(Locale.ENGLISH).replaceAll("[^a-z0-9\\s]", " ");
    }
}
