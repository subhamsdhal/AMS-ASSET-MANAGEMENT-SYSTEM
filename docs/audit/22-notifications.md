# Module 22 Audit — Notifications

**Scope:** In-app/email notification infrastructure — `NotificationHelper`, `NotificationService`, `NotificationEventService`, `NotificationRecipientResolver`, `EmailService`, and the admin-facing `UpdateNotificationSettingsServlet`/`notification_settings.jsp`.
**Verification layers used:** (a) static code reading — full for the mechanisms described below. (b)/(c) not performed this pass (no live SMTP send attempted).

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Notifications (in-app) | [notifications.jsp](src/main/webapp/notifications.jsp) | In-app notification feed |
| Notification Settings | [notification_settings.jsp](src/main/webapp/notification_settings.jsp) | Admin-configurable SMTP + alert-threshold settings |
| Alert Center | [alert_center.jsp](src/main/webapp/alert_center.jsp) | Consolidated alerts view |
| Overdue Actions | [overdue_actions.jsp](src/main/webapp/overdue_actions.jsp) | Cross-module overdue-item feed |
| Test Email | [test_email.jsp](src/main/webapp/test_email.jsp) / `SendTestEmailServlet` | Admin-triggered SMTP connectivity test |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| V1 | Save Notification Settings | notification_settings.jsp form | native POST | `POST /UpdateNotificationSettingsServlet` | not fully re-traced this pass beyond the role check | `system_settings` | — | SUPER_ADMIN/ADMIN ([UpdateNotificationSettingsServlet.java:40](src/main/java/com/mycompany/asset_management_system_ams/UpdateNotificationSettingsServlet.java:40)), matches `adminOnly` | Not confirmed | n/a | Not assessed | Code | **CODE LOOKS CORRECT, BUT see Finding 1 — the settings this page saves do not control most of the application's actual email traffic** | — | See Finding 1 |
| V2 | Send Notification (the actual mechanism, invoked internally by ~41 other files across every module audited so far) | n/a — internal API, not a page | n/a | n/a | [NotificationHelper.sendNotification](src/main/java/com/mycompany/asset_management_system_ams/NotificationHelper.java) → [NotificationService](src/main/java/com/mycompany/asset_management_system_ams/NotificationService.java) | `email_logs`/`notification_logs` | n/a | n/a (internal) | n/a | This **is** the notification | n/a | Code | **BROKEN / MISCONFIGURED — see Finding 1 and Finding 2** | **Critical** | See Findings 1 and 2 below |

### Finding 1 (Critical, architectural) — Two entirely separate, independently-configured email-sending mechanisms exist, and the one an admin can actually control handles only a small fraction of the application's real notification traffic

A full-codebase caller count reveals a striking split:

- **`NotificationHelper`** (which internally delegates to `NotificationService` for the actual SMTP send) is called from **41 different files** — this is, practically speaking, the entire application's notification system: every asset/allocation/return/disposal/maintenance/request/vendor/department/employee/QR/physical-verification alert audited across Modules 1–21 routes through this path.
- **`EmailService`** (which reads its SMTP host/port/username/password from `SettingsDAO`, i.e., the database-backed settings that `notification_settings.jsp`/`UpdateNotificationSettingsServlet` actually let an admin edit) is called from only **3 files**: `AddEmployeeServlet`, `SaveSettingsServlet`, and `WarrantyAlertScheduler` (Module 14's warranty-expiry scheduler).

Tracing `NotificationService.loadNotificationProperties()` and `sendEmailUsingPort()` confirms `NotificationHelper`'s path reads its SMTP host/port and Gmail username/app-password **exclusively from the static file `/WEB-INF/notification.properties`**, never from `SettingsDAO`/`system_settings` at all — the two mechanisms don't merely duplicate each other, they are **completely disconnected data sources for the same underlying purpose**. The practical consequence: **an administrator changing the SMTP configuration on `notification_settings.jsp` — a page explicitly presented as controlling this — has no effect whatsoever on the vast majority of the application's actual outbound email**, since that traffic is hardcoded to a static file the UI never touches. Only a handful of code paths (a subset of employee-creation, settings-save confirmation, and the warranty scheduler) actually honor the admin-configured settings; everything else silently and permanently uses whatever is baked into `notification.properties`. This is a genuine, high-consequence functional defect masquerading as a working settings page — it would pass a shallow UI test ("the form saves without error") while never actually achieving what a reasonable admin would expect it to do.

### Finding 2 (Critical, security — re-confirms and updates a previously-flagged issue) — `WEB-INF/notification.properties` still contains a live, plaintext Gmail App Password, checked into the repository and actively used at runtime

The Phase-0 module inventory flagged this file based on `CHANGELOG-fixes.md`'s prior documentation of "an explicitly unrotated leaked Gmail credential." **This audit independently re-confirms the file still exists, still contains what appears to be a live 16-character Gmail App Password in plaintext, and — per Finding 1 — is not a vestigial leftover but the actual, currently-active credential source for the overwhelming majority of this application's email sending.** (The specific credential value is deliberately not reproduced in this report; see the file directly at `src/main/webapp/WEB-INF/notification.properties` if verification is needed.) Because this file lives inside `src/main/webapp/WEB-INF/` — a location that is bundled into the deployed WAR — and because the repository itself is what this audit was run against, **anyone with read access to this source repository has the live SMTP-sending credential for whatever Gmail account is configured there.** An App Password grants the ability to send email as that account via SMTP; combined with Finding 1 (this is the credential actually used for real notification traffic), this is not a dormant/decorative secret — it is load-bearing and exposed simultaneously. This should be treated as the single highest-priority security finding across this entire audit series: rotate the credential immediately, remove it from source control (and from Git history, not just the working tree, if it was ever committed), and migrate `NotificationService`'s credential source to the same DB-backed `SettingsDAO` mechanism `EmailService` already correctly uses (which would also resolve Finding 1 in the same fix).

---

## 3. Business Workflow / Lifecycle Check

- **Every notification-triggering event across the 21 modules audited so far correctly calls into `NotificationHelper`** — the *event-triggering* discipline is good (this audit did not find a single module that silently skipped notifying on a significant state change); the problem identified here is entirely in *where the credentials for actually sending it come from*, not in *whether the code remembers to try*.
- **`SendTestEmailServlet`** (admin-triggered connectivity test) calls into `NotificationService` (confirmed via grep) — meaning the "Test Email" feature on the Settings page **does** exercise the properties-file-backed path, which means an admin running a test email would get a result that's actually representative of the real notification traffic's behavior (good), but the *settings changes* they might make right next to that test button on the same page would not actually affect that same path (Finding 1) — a confusing, misleading juxtaposition if true (worth confirming at runtime exactly how `test_email.jsp` is wired, since this is inferred from caller lists rather than a full trace of that specific servlet).

---

## 4. Data Model Check

Not independently re-read in full this pass — `email_logs`/`notification_logs` tables (per the Phase-0 inventory) presumably capture send attempts/outcomes; `system_settings` holds the (partially-honored) SMTP configuration. No additional findings beyond Findings 1–2.

---

## 5. Status Model Check

Not applicable — this module is a delivery mechanism, not a stateful business entity.

---

## 6. RBAC & Security Check

- **Finding 2 is the dominant security concern of this entire audit.**
- **CSRF**: app-wide gap; low incremental relevance to this module specifically (settings changes here are non-destructive/reversible).
- **RBAC on settings**: correctly restricted to SUPER_ADMIN/ADMIN.
- **Recipient resolution** (`NotificationRecipientResolver`) is correctly scoped to active users/employees only, with no obvious over-broad disclosure pattern found in the portion read.

---

## 7. Audit Log & Data Integrity Check

- Email send attempts are logged (per `EmailService`'s own doc comment and the general pattern observed) — not independently re-verified for the `NotificationService` path specifically this pass, flagged as a follow-up.
- Finding 1 is itself a data-integrity concern in a broader sense: the `system_settings` table can hold SMTP configuration values that are silently non-authoritative for most of the system's actual behavior — an admin reading back their own saved settings would see values that look correctly persisted and have no way to know, from the UI alone, that they're not being used.

---

## 8. Missing Features / Gaps

- **Finding 1**: dual, disconnected email-configuration mechanisms.
- **Finding 2**: live leaked credential.
- Not confirmed this pass whether `notification.properties` is `.gitignore`d going forward (even after rotation, if it isn't, a future regeneration risks the same exposure) — worth checking as part of the remediation.

---

## 9. Advanced Feature Recommendations

- **P0 — Rotate the Gmail App Password immediately** (Finding 2), independent of any code changes, since the credential's exposure is a fact of the repository's history regardless of what happens next.
- **P0** — Consolidate `NotificationService`'s credential source onto `SettingsDAO`/`system_settings` (the same mechanism `EmailService` already correctly uses), eliminating `notification.properties` entirely — this single change resolves both Finding 1 (settings become actually authoritative) and prevents Finding 2 from recurring (no more static credential file to accidentally commit).
- **P0** — Remove `notification.properties` from version control (and confirm whether it needs purging from git history, not just the current tree, depending on the repository's actual hosting/exposure situation — a decision for the user/team, not this audit, but worth flagging explicitly).
- **P1** — Add a `.gitignore` entry (or equivalent) for any local secrets file going forward, and consider environment-variable or secrets-manager-based configuration for SMTP credentials rather than either a properties file or a plain DB column, given this is a "live world deployment" per this codebase's own prior-fix comments.
- **P2** — Clarify `test_email.jsp`'s relationship to the two mechanisms once Finding 1 is resolved, so there's exactly one settings surface and one send path.

---

## 10. Test Cases

- [ ] **Regression test for Finding 1 (before any fix)**: change the SMTP host/username in `notification_settings.jsp`, then trigger any ordinary business notification (e.g. Add Asset) — confirm it **still** uses the old `notification.properties` values, not the newly-saved settings (documents the current, undesired behavior)
- [ ] **Regression test for Finding 1 (after the recommended fix)**: repeat the above and confirm the newly-saved settings are now what's actually used
- [ ] Confirm `SendTestEmailServlet`'s test send and a real business notification currently use the *same* underlying credentials (both via `NotificationService`) — if true, this is useful evidence the "test" is at least representative of real traffic today, worth preserving as a property of whatever the fixed architecture looks like
- [ ] **Security**: confirm (with the repository owner) whether `notification.properties`'s credential has ever been exposed via a public remote (GitHub, etc.) — if so, treat rotation as forensically urgent, not just good hygiene
- [ ] **RBAC**: EMPLOYEE/AUDITOR/ASSET_MANAGER/DEPARTMENT_HEAD cannot POST to `UpdateNotificationSettingsServlet`
- [ ] **Functional**: after credential rotation and (ideally) the consolidation fix, confirm at least one real notification from each of the 21 previously-audited modules still successfully sends

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 5 | Notifications fire reliably across every module, but the admin-facing configuration for them is largely non-functional (Finding 1) |
| Lifecycle support | N/A | Not a lifecycle-bearing module |
| Data integrity | 4 | `system_settings` can hold SMTP values that silently aren't authoritative |
| UX | 3 | The Settings page actively misleads an admin about what it controls |
| Validation | Not assessed | Not traced in this pass |
| RBAC | 8 | Correct on the one control point checked |
| Security | 1 | **A live, actively-used SMTP credential is checked into source control** — this is as close to a worst-case finding as this audit series has produced |
| API integration | 4 | Two disconnected mechanisms for the same purpose |
| DB integrity | 5 | Not itself broken, but rendered partially meaningless by Finding 1 |
| Auditability | Not fully assessed | Send-attempt logging exists per code comments, not independently re-verified |
| Reliability | 6 | The actual sending mechanism (however credentialed) appears to function; async, non-blocking, doesn't crash the app if unconfigured |
| Performance | 7 | Async thread-pool-based sending, no blocking observed |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Not applicable |

**Overall status: NOT READY**

This module contains the single most serious finding of the entire audit series: a live, actively-used SMTP credential checked into the repository, compounded by an architectural split that makes the admin-facing settings page that should control it almost entirely non-functional. Neither finding is subtle or requires deep inference — both are directly, unambiguously confirmed by reading the code and the file in question — and both should be treated as immediate priorities ahead of every other finding in this audit, including the two Critical RBAC bugs found in Module 2.
