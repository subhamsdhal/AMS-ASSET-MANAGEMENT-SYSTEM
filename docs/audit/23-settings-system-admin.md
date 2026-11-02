# Module 23 Audit — Settings & System Administration

> **Update (2026-08-22):** Full settings.jsp sweep for dead links/errors, on direct request. Static
> check first: every `href`, form `action`, and JS `fetch()` target cross-referenced against real
> files/servlets - all clean, no 404s, no missing servlets, no field-name mismatches with
> `SaveSettingsServlet`. Live click-through of all 8 tabs and every link found the same - all 21
> internal links returned real HTTP 200s, no console errors, no broken tab-switching.
>
> One genuine bug found live, in the QR & Mobile tab's "Mobile Tunnel" controls: none of the five
> tunnel JS functions (`startTunnel`/`stopTunnel`/`checkTunnelStatus`/`setManualUrl`/`clearTunnelUrl`)
> checked `response.ok` before treating a parsed JSON body as a success payload.
> `TunnelControlServlet` deliberately returns HTTP 403 with a real `{"error": "..."}` body when mobile
> tunnel control is disabled for the deployment (a genuine, intentional security-hardening decision
> from this servlet's own history - not something this pass touched or should touch) - `fetch()` does
> not reject on a 4xx status, so every one of these functions silently misread that 403 as a normal
> response. Confirmed live: a stale "Running" badge and a long-dead saved ngrok URL from earlier
> testing stayed displayed as an apparently-live clickable link even after clicking "Refresh Status,"
> which itself reported the honest 403 as a vague "No active tunnel" instead of the real reason. Worse,
> `setManualUrl`/`clearTunnelUrl` showed an outright false SUCCESS message ("Tunnel URL saved" /
> "Tunnel URL cleared") on a request the server had actually rejected before ever touching the
> database - confirmed the underlying `ams.qr.mobile_tunnel_url` value was genuinely untouched by
> querying it directly. Fixed via a shared `parseTunnelResponse()` helper checking `response.ok` for
> all five actions - a disabled/failed request now always surfaces the server's real reason and never
> applies an "as if it worked" UI update. Verified live for all three previously-broken cases plus
> `startTunnel`/`stopTunnel`: each now shows the honest disabled-deployment message, the badge
> correctly resets to "Unavailable" instead of a stale "Running," and no false-success state is shown
> for a rejected save/clear. Normal settings saves (tested via the Organization tab) still work
> correctly end to end. Full project suite: 191/191 green throughout - this was a pure JSP/JS fix, no
> Java changes, so no new automated test coverage was added; the fix was verified live instead, the
> same way this file's own methodology treats settings.jsp elsewhere.

**Scope:** Global system settings (`SaveSettingsServlet`, `SettingsDAO`), currency settings (`UpdateCurrencySettingsServlet`), and the highest-consequence actions in the entire application — database backup and restore (`BackupDatabaseServlet`, `RestoreDatabaseServlet`). Notification settings are cross-referenced to Module 22's dominant finding rather than re-analyzed here.
**Verification layers used:** (a) static code reading — full for backup/restore. (b)/(c) not performed this pass — deliberately: actually exercising a database restore against a live system is exactly the kind of high-consequence action this audit's own methodology (§11, "never mark something VERIFIED WORKING... that can't be executed here") counsels against attempting without explicit, separate authorization.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Settings | [settings.jsp](src/main/webapp/settings.jsp) | Hub for all system configuration |
| Currency Settings | [currency_settings.jsp](src/main/webapp/currency_settings.jsp) | Display currency configuration |
| Backup & Restore | [backup_restore.jsp](src/main/webapp/backup_restore.jsp), [database_backup_export.jsp](src/main/webapp/database_backup_export.jsp) | Full-database SQL backup download and restore-from-file |
| DB Status | [db_status.jsp](src/main/webapp/db_status.jsp) | Connection/health diagnostic |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W1 | Download Database Backup | backup_restore.jsp link | native **GET** | `GET /BackupDatabaseServlet` | [BackupDatabaseServlet.doGet](src/main/java/com/mycompany/asset_management_system_ams/BackupDatabaseServlet.java:47) | reads all tables (write-free) | n/a (read-only) | SUPER_ADMIN/ADMIN | Not confirmed in the portion read | Not confirmed | n/a | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Streams a generated `.sql` dump directly to the HTTP response as a forced download (`Content-Disposition: attachment`) — never written to a web-accessible directory on disk, so there's no persistent-file exposure risk from the backup mechanism itself. Being a GET is low-risk here specifically (this is a read-only export, not a state change, and cross-origin script can't read the response body of a forced-download GET even if silently triggered) — a materially different risk profile from the GET-state-change bugs found and fixed elsewhere in this codebase (Modules 9, 15, 16, 17), correctly not needing the same fix |
| W2 | Restore Database from Backup | [backup_restore.jsp](src/main/webapp/backup_restore.jsp) form | native POST (multipart) | `POST /RestoreDatabaseServlet` | [RestoreDatabaseServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/RestoreDatabaseServlet.java:32) | **writes to every table** — executes arbitrary statements from the uploaded file | Requires an exact typed confirmation string (`"RESTORE RAILWAY AMS"`); file must have a `.sql` extension; a real, hand-rolled SQL-statement splitter correctly respects quoted strings/comments (doesn't naively split on every semicolon, which would corrupt statements containing string literals with semicolons) | SUPER_ADMIN/ADMIN | Yes — both success and failure produce an `AuditDAO.log()` entry plus a dedicated admin security-alert email with an explicit "Security Note" reminder ([RestoreDatabaseServlet.java:181-211](src/main/java/com/mycompany/asset_management_system_ams/RestoreDatabaseServlet.java:181)) — this is the most thoroughly-alerted single action found anywhere in this audit | Yes, as above | `?error=confirm/nofile/invalid/db/server`, `?msg=restored&count=N` | Code | **CODE LOOKS CORRECT, BUT see Finding 1** | **Critical (operational, not a security vulnerability)** | **See Finding 1 below** |

### Finding 1 (Critical, operational risk) — Restore executes statement-by-statement with no transaction wrapping and no automatic pre-restore safety backup

`RestoreDatabaseServlet` reads the uploaded `.sql` file, splits it into individual statements, disables foreign-key checks, and executes each statement **one at a time via `Statement.execute()`** in a loop ([RestoreDatabaseServlet.java:101-117](src/main/java/com/mycompany/asset_management_system_ams/RestoreDatabaseServlet.java:101)) — there is no surrounding `con.setAutoCommit(false)`/transaction, and no attempt to snapshot or back up the *current* database state before beginning. **If the uploaded script fails partway through** (a malformed statement, a constraint violation despite FK checks being disabled, a timeout, a truncated/corrupted upload) **the database is left in whatever partial state execution reached — some tables fully restored to the backup's contents, others untouched from before, with no automatic way to return to either the pre-restore state or complete the interrupted restore.** The `finally` block does correctly re-enable foreign key checks regardless of outcome, and the failure path does correctly alert an admin via email — but neither of those mitigates the actual data state left behind. For an operation whose entire purpose is disaster recovery, this is a significant risk: **the recovery mechanism itself has no rollback safety net**, meaning a bad backup file, a truncated upload, or an unexpected statement could turn a routine restore into a second incident requiring its own recovery. This is flagged as an operational/reliability finding, not a security vulnerability — the access control and confirmation-friction around triggering a restore are both reasonably solid (see §6).

---

## 3. Business Workflow / Lifecycle Check

- **The typed-confirmation pattern (`"RESTORE RAILWAY AMS"`) is good friction against an accidental click**, but it is worth being precise about what it does and doesn't protect against: it is **not** a CSRF defense in the way a session-bound anti-CSRF token would be — an attacker forging a cross-site request could, in principle, include the literal correct string in a forged form field just as easily as any other value, since the string is a fixed, publicly-knowable constant, not a per-session secret. In practice, though, exploiting this specific endpoint via classic cross-site CSRF is meaningfully harder than most other CSRF-exposed actions in this app, because the request also requires a `multipart/form-data` file upload (`backupFile`) — and browsers do not allow cross-origin JavaScript to programmatically populate a file `<input>` with attacker-controlled content; genuine file selection requires direct user interaction with a file picker on the actual page. **This means blind, classic CSRF cannot fully weaponize this endpoint** (an attacker's forged cross-site form could supply the confirmation text but not a malicious SQL payload as a real file part) — the practical residual risk is same-origin script execution (e.g. a hypothetical XSS vulnerability elsewhere in the app, none confirmed in this audit series) combined with an authenticated ADMIN/SUPER_ADMIN session, which is a higher bar than plain CSRF. Worth documenting this reasoning explicitly rather than either over- or under-stating the risk.
- **Backup's table list (`PRIORITY_ORDER`) is a curated, ordered subset** ([BackupDatabaseServlet.java:30-44](src/main/java/com/mycompany/asset_management_system_ams/BackupDatabaseServlet.java:30): `roles, departments, users, employees, asset_categories, vendors, assets, asset_requests, asset_allocation, asset_returns, maintenance_logs, asset_disposal, audit_logs`) — **notably, this is a partial table list relative to the ~40+ tables this schema actually has** (per Module 1's original inventory count). Tables not in this list (e.g. `physical_verification`-family tables, QR/scan-log tables, `warranty_renewals`, `profile_change_requests`, `notification`/`email_logs`, `category_vendor_mapping`, and others audited across this entire series) are **not confirmed to be included in the backup at all** unless the servlet has additional logic beyond this priority list that wasn't fully traced in this pass (worth a direct follow-up: does `PRIORITY_ORDER` define *export ordering* for FK-dependency reasons with all other tables still included afterward, or does it define the *complete list* of what gets backed up? This distinction matters enormously — if it's the latter, a "backup" that silently omits a third or more of the schema is a significant, quietly incomplete disaster-recovery capability).

---

## 4. Data Model Check

Not applicable in the traditional sense — this module operates on the whole database rather than owning specific tables. `system_settings` (Module 8/22) is the settings store; SMTP password specifically is stored **encrypted** (`decryptSettingValue()`/`getSmtpPassword()`, [SettingsDAO.java:235-236](src/main/java/com/mycompany/asset_management_system_ams/SettingsDAO.java:235)) — a meaningful, positive point of contrast with Module 22's Finding 2: the database-backed settings mechanism (the one barely used, per Module 22) actually handles its credential correctly at rest, while the properties-file mechanism (the one that's actually load-bearing for real traffic) does not. This makes Module 22's recommended fix (consolidate onto the DB-backed path) even more clearly correct — it wouldn't just fix the architectural split, it would also upgrade the credential's at-rest protection.

---

## 5. Status Model Check

Not applicable.

---

## 6. RBAC & Security Check

- **RBAC on both Backup and Restore is correctly restricted to SUPER_ADMIN/ADMIN.**
- **CSRF**: app-wide gap for W1 (low practical impact, per §2); W2 has partial, incidental protection via the file-upload browser restriction discussed in §3, not a designed defense — worth adding real CSRF tokens regardless, as defense-in-depth against the residual same-origin-script risk.
- **Arbitrary SQL execution is inherent to a restore feature's purpose**, not itself a flaw — the real question is whether the *access* to trigger it is adequately controlled (yes, RBAC + confirmation) and whether *failure* is handled safely (no — Finding 1).
- **No apparent limit on restore file size beyond the `@MultipartConfig` cap** (50MB file / 60MB request) — reasonable for a real database dump, not flagged as a concern.

---

## 7. Audit Log & Data Integrity Check

- **This module has the most thorough alerting of any single action audited in this entire series** — both success and failure of a restore trigger a dedicated admin security-alert email, in addition to the standard audit log entry, with an explicit human-readable "Security Note" reminding the recipient to verify the restored data. This is exactly the level of ceremony an action this consequential deserves.
- **Finding 1 is the dominant integrity concern**: the alerting tells an admin *that* a restore happened and whether it reported success/failure, but does nothing to protect against or recover from the *data-level* inconsistency a partial failure would leave behind.
- **The scope question about `PRIORITY_ORDER`** (§3) is also a data-integrity concern if backups are silently incomplete — this needs direct confirmation before this module's backup capability can be trusted as a genuine disaster-recovery tool.

---

## 8. Missing Features / Gaps

- **Finding 1**: no transactional safety or automatic pre-restore backup.
- **Backup table-list scope is unconfirmed** — needs a direct check of whether `PRIORITY_ORDER` is the complete export list or just an ordering hint.
- No restore *dry-run*/*validation* mode (parse and sanity-check the uploaded script before executing anything) — would catch a malformed file before any damage, complementing a transactional fix rather than replacing it.
- No visible backup *retention*/*scheduling* — this appears to be a fully manual, on-demand, one-shot action with no automated recurring backup found anywhere in this codebase (worth confirming, since automated backups are standard expectation for a production system managing real organizational assets).

---

## 9. Advanced Feature Recommendations

- **P0** — Wrap the restore's statement execution in a transaction where the underlying storage engine/statement types allow it (note: some DDL statements auto-commit in MySQL regardless of transaction wrapping — if the backup format includes `CREATE TABLE`/`DROP TABLE` DDL, full transactional safety may not be fully achievable this way, in which case the stronger fix is:) **automatically take a fresh safety backup immediately before executing any restore**, so a failed/bad restore can always be manually reverted to the immediately-prior state even if the restore itself can't be atomically rolled back mid-flight.
- **P0** — Confirm and fix the backup scope question (§3) — if tables are being silently omitted, this is a critical disaster-recovery gap that should be resolved before this feature is relied upon.
- **P1** — Add a restore dry-run/validation pass (parse the file, check statement count and basic sanity, surface it to the admin) before committing to execution.
- **P1** — Real CSRF tokens on both endpoints, as defense-in-depth beyond the incidental file-upload protection.
- **P2** — Automated, scheduled backups with retention, rather than relying entirely on an admin remembering to manually trigger one.
- **P3** — Consider a size/statement-count sanity check with an explicit warning if a restore file looks unusually small relative to the live database (a possible sign of a truncated/corrupted upload) before proceeding.

---

## 10. Test Cases

No dedicated test file found for this module in the Phase-0 inventory — directly relevant given the stakes involved; a disaster-recovery feature with no automated regression coverage is itself worth flagging.

- [ ] **Functional**: a valid backup file downloads successfully and, when fed back through Restore, round-trips the data correctly (a full backup→restore→verify cycle against a disposable test database, never production)
- [ ] **Regression test for the backup-scope question**: compare the set of tables actually present in a generated backup file against the full live schema's table list — confirm whether any tables are silently missing
- [ ] **Regression test for Finding 1**: construct a `.sql` file that is valid for its first N statements and then contains a deliberately malformed statement — run it through Restore against a disposable test database and confirm/document the resulting partial state (this documents current behavior; the fix should change what this test asserts)
- [ ] **Negative/Boundary**: missing/incorrect confirmation text is rejected; non-`.sql` file extension is rejected; empty file is rejected
- [ ] **RBAC**: EMPLOYEE/AUDITOR/ASSET_MANAGER/DEPARTMENT_HEAD cannot reach either endpoint
- [ ] **Security**: confirm a cross-site auto-submitting form (no real file-picker interaction) cannot successfully trigger a restore, validating the reasoning in §3
- [ ] Confirm both success and failure paths correctly send the admin security-alert email and write the audit log entry
- [ ] **DB integrity**: confirm foreign key checks are correctly re-enabled even when the statement loop throws partway through (the `finally` block's re-enable — should currently pass, worth a regression guard)

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 6 | Backup/restore both work for the happy path; the scope and failure-safety questions are real gaps |
| Lifecycle support | N/A | Not a lifecycle-bearing module |
| Data integrity | 4 | Finding 1 is a genuine, high-consequence gap for a disaster-recovery feature |
| UX | 7 | The typed-confirmation friction and thorough alerting are good UX for a dangerous action |
| Validation | 6 | Good input validation (extension, confirmation text); no content-level validation of the SQL itself before execution |
| RBAC | 8 | Correct, consistent |
| Security | 6 | No CSRF tokens (though partially, incidentally mitigated for Restore specifically); credential-at-rest handling for the DB-backed settings path is actually good (encrypted) |
| API integration | 7 | Consistent conventions |
| DB integrity | 5 | The restore mechanism's lack of transactional/rollback safety is the central concern |
| Auditability | 9 | The best-alerted action in the entire audit — a genuine standout |
| Reliability | 4 | Finding 1 directly threatens reliability of the one feature whose whole job is reliability recovery |
| Performance | Not assessed | Large-file/large-statement-count behavior not tested this pass |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Not applicable |

**Overall status: MAJOR WORK REQUIRED**

The access-control and alerting discipline around this module's most dangerous actions is genuinely excellent — better than almost anything else audited so far. But the core reliability property a backup/restore feature exists to provide — "you can always get back to a known-good state" — is not actually guaranteed by the current restore implementation, and the backup's completeness is an open, unverified question. For a feature whose entire purpose is disaster recovery, both of these need to be resolved with high confidence before this module can be trusted in a real incident.
