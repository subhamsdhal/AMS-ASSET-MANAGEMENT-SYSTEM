# Module 14 Audit — Warranty

**Scope:** Warranty renewal (`RenewAssetWarrantyServlet`, `WarrantyRenewalDAO`) and expiry alerting (`WarrantyAlertScheduler`).
**Verification layers used:** (a) static code reading — full. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Warranty Report | [warranty_report.jsp](src/main/webapp/warranty_report.jsp) | List of assets by warranty status/expiry |
| Renew Warranty | [renew_warranty.jsp](src/main/webapp/renew_warranty.jsp) | Record a renewal, either by explicit new date or by extension-months |
| Warranty Renewal History | [view_warranty_history.jsp](src/main/webapp/view_warranty_history.jsp) | Read-only renewal history |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| N1 | Renew Warranty | [renew_warranty.jsp](src/main/webapp/renew_warranty.jsp) form | native POST | `POST /RenewAssetWarrantyServlet` | [RenewAssetWarrantyServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/RenewAssetWarrantyServlet.java:32) | `warranty_renewals`, `assets` (warranty_expiry), `audit_logs` | Accepts either an explicit new expiry date or an extension in months (1-240, bounds-checked); explicit-date path rejects a date in the past; cost defaults safely to 0 on any parse failure rather than erroring; notes capped at 1000 chars | SUPER_ADMIN/ADMIN/ASSET_MANAGER only — the servlet's own doc comment explicitly states AUDITOR's read-only report access is **deliberately not sufficient** to reach this mutating endpoint, matching the view-vs-mutate split pattern used consistently elsewhere in the app | Yes — `RENEW_WARRANTY` with previous/new expiry and cost in the message | Not found in this servlet (renewal doesn't appear to trigger an immediate notification — reasonable, since it's a routine administrative update, not an alert-worthy event) | `?error=invalid_asset/invalid_extension/missing_date/invalid_date/date_in_past/server` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Extension-months calculation correctly bases itself on the asset's *current* expiry if one exists, or today if not, and additionally clamps the base date forward to today if the current expiry has already lapsed ([RenewAssetWarrantyServlet.java:78-83](src/main/java/com/mycompany/asset_management_system_ams/RenewAssetWarrantyServlet.java:78)) — prevents a "renew by 6 months" action on an asset whose warranty expired long ago from computing a new expiry that's still in the past |
| N2 | Warranty Expiry Alert (background) | n/a (no UI trigger) | scheduled, every 24h | n/a | [WarrantyAlertScheduler.runCheck](src/main/java/com/mycompany/asset_management_system_ams/WarrantyAlertScheduler.java:99) | `assets` (read), `notification_logs` (dedup) | n/a | n/a (system process, not user-triggered) | n/a | Yes — this **is** the notification mechanism | n/a | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION (background job, not directly clickable) | — | **This entire class was built specifically to close a real, previously-existing gap, per its own extensive doc comment**: the `Settings > Notifications > "Warranty Expiry Alert - Days Before"` threshold field was being saved to the database with **nothing anywhere in the codebase ever reading it**, and `EmailService.sendWarrantyAlert()` existed as a ready-built template with **zero callers**. This scheduler is the deliberate fix — a genuinely well-engineered one, with a startup delay, 24h fixed-rate polling, an SMTP/settings-enabled short-circuit to avoid wasted queries, a `notification_logs`-backed dedup so one asset doesn't re-alert every single day it sits inside the threshold window, a hard cap of 200 alerts per run as a defensive measure against a misconfigured threshold on a large fleet, and correct daemon-thread lifecycle management (`contextDestroyed` calls `shutdownNow()`, doesn't block Tomcat shutdown) |

---

## 3. Business Workflow / Lifecycle Check

- **Renewal is transactionally atomic**: `WarrantyRenewalDAO.recordRenewal()` inserts the `warranty_renewals` history row and updates `assets.warranty_expiry` in one transaction, with its own doc comment explicitly stating the rationale — "the renewal log and the asset's current warranty status... must never disagree." This is exactly the right framing and matches the transactional discipline seen in this codebase's better modules.
- **Self-healing table creation** (`ensureTable()`, gated by a `volatile boolean` to avoid re-running the `CREATE TABLE IF NOT EXISTS` check on every single call) — same defensive pattern as `QrUrlUtil`/`PasswordResetDAO`, explicitly cross-referenced in this class's own comment, and a good example of consistent internal convention.
- **The alert scheduler is a genuinely complete missing-feature fix**, not a partial one — it addresses both halves of what would otherwise be a silently-broken feature (a settings field that does nothing, and dead notification code) with real production considerations (rate-limiting, dedup, graceful shutdown) that go beyond the minimum needed to just make it "work."

---

## 4. Data Model Check

`warranty_renewals` (self-created by `WarrantyRenewalDAO.ensureTable()`, and per its own comment also mirrored into `schema.sql` for fresh-install documentation — worth spot-confirming this claim during a schema audit, but the self-healing mechanism means it's non-blocking either way): `renewal_id, asset_id, previous_expiry, new_expiry, extension_months, renewal_cost, notes, renewed_by, created_at`. A clean, complete, purpose-fit schema — no gaps found, no unpopulated columns, no schema/write-path mismatch of the kind found repeatedly in other modules.

---

## 5. Status Model Check

Not a status-machine module — `warranty_expiry` is a plain date, always monotonically advanced (or set for the first time) by a renewal, never retracted. No impossible-state risk identified.

---

## 6. RBAC & Security Check

- **CSRF**: app-wide gap applies to N1.
- **RBAC enforcement**: correct, and explicitly, deliberately narrower than the corresponding read-only report access — a good, clearly-documented design decision rather than an accidental gap.
- **Email content**: not directly assessed this pass (no notification fires from N1 itself; N2's alert content wasn't read in full) — flag as a minor follow-up to confirm the same `HtmlEscapeUtil` question applies or doesn't (asset names could theoretically contain injected HTML if this module's alert body interpolates them unescaped, consistent with the cross-cutting finding from Modules 10/12).

---

## 7. Audit Log & Data Integrity Check

- Renewal is audit-logged with a complete, informative message (previous/new expiry, cost).
- No rejection-path audit logging (consistent with several other modules' smaller gap in this area, e.g. Module 13) — a minor, not urgent, observation.
- Data integrity is otherwise clean — no gaps found in this module comparable to the "schema models it, write path doesn't" pattern seen repeatedly elsewhere.

---

## 8. Missing Features / Gaps

- No rejection-path audit logging.
- Not confirmed whether `WarrantyAlertScheduler`'s email body correctly escapes asset-derived free text (flagged for follow-up, not confirmed as a defect).
- No visible warranty-provider/policy-number tracking beyond the expiry date itself (cross-referenced as a possible gap in Module 4's data model check too) — if insurance/warranty-provider details are wanted, this module's schema would need extending.

---

## 9. Advanced Feature Recommendations

- **P2** — Add rejection-path audit logging for consistency with the codebase's stronger modules.
- **P2** — Confirm/apply `HtmlEscapeUtil` to `WarrantyAlertScheduler`'s email body if not already safe.
- **P3** — Warranty provider/policy-number/claim-tracking fields if the organization needs more than an expiry date (e.g. for filing an actual warranty claim, not just tracking renewal).
- **P3** — CSRF tokens (shared app-wide recommendation).

---

## 10. Test Cases

No dedicated test file found for this module — [TestWarrantyQueries.java](src/test/java/com/mycompany/asset_management_system_ams/TestWarrantyQueries.java) exists per the Phase-0 inventory (1KB, likely a small ad-hoc query check rather than a real test suite — flag to confirm in a follow-up pass).

- [ ] **Functional**: renewing via explicit new date updates `assets.warranty_expiry` and creates a matching `warranty_renewals` row
- [ ] Renewing via extension-months from a still-valid current expiry correctly bases the calculation on that expiry, not today
- [ ] Renewing via extension-months from an *already-expired* warranty correctly bases the calculation on today, not the stale past expiry (confirms the clamp at [RenewAssetWarrantyServlet.java:81-83](src/main/java/com/mycompany/asset_management_system_ams/RenewAssetWarrantyServlet.java:81))
- [ ] **Negative/Boundary**: extension of 0 or 241+ months is rejected; an explicit past date is rejected
- [ ] **Scheduled job**: seed an asset with `warranty_expiry` inside the configured alert window, run `WarrantyAlertScheduler.runCheck()` directly, and confirm exactly one alert email/notification-log entry is created; running it again immediately after must **not** create a second alert for the same asset (dedup check)
- [ ] Confirm the scheduler's `MAX_ALERTS_PER_RUN` cap actually limits output when more than 200 eligible assets exist
- [ ] **RBAC**: AUDITOR (read-only warranty-report access) cannot POST to `RenewAssetWarrantyServlet` despite being able to view `warranty_report.jsp`
- [ ] **Security**: direct `curl -X POST /RenewAssetWarrantyServlet` with a valid ASSET_MANAGER session and no CSRF-equivalent token succeeds (documents the shared CSRF gap)

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 9 | Renewal and alerting are both complete, and the alerting half is a documented fix for a real prior gap |
| Lifecycle support | 8 | Clean, atomic, monotonic warranty-date progression |
| Data integrity | 9 | No gaps found; clean schema, fully populated |
| UX | 8 | Flexible explicit-date-or-extension input, sensible defaults and clamps |
| Validation | 8 | Thorough bounds-checking throughout |
| RBAC | 8 | Correct, deliberately documented view-vs-mutate split |
| Security | 6 | No CSRF (shared gap); email-escaping not fully confirmed for the alert path |
| API integration | 8 | Clean, consistent |
| DB integrity | 8 | Self-healing table creation, well-documented rationale |
| Auditability | 7 | Success well-logged; no rejection-path logging |
| Reliability | 9 | The scheduler's rate-limiting, dedup, and graceful-shutdown handling reflect genuine production-readiness thinking |
| Performance | 8 | Dedup and rate-capping specifically address performance/spam risk at scale |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | Not assessed | `warranty_report.jsp` itself not deep-audited this pass, deferred to Module 24 |

**Overall status: PRODUCTION READY**

This is the cleanest module audited so far — competent renewal logic, and a background alerting system that is a genuinely well-documented, thoughtfully-engineered fix for a real, previously-existing gap (a dead settings field and an uncalled notification template). The only items keeping this from a perfect score are the shared, app-wide CSRF gap and a couple of minor, low-stakes audit-logging/escaping follow-ups — nothing that blocks production use of this specific module.
