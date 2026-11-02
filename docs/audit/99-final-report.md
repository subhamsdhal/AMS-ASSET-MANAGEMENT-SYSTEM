# IR-AMS (Railway Asset Management System) — Final Production-Readiness Audit Report

**Audited repo:** `Asset_Management_System_AMS` — "IR-AMS / Railway AMS — East Coast Railway Asset Management System"
**Stack:** Jakarta EE 10 (Servlet 6.0 + JSP/JSTL), MySQL via raw JDBC (no ORM), Maven/WAR, no SPA framework — see [00-module-inventory.md](00-module-inventory.md) for full stack detail.
**Methodology:** 28 modules individually audited end-to-end (UI → handler → API → DB → response → audit log → notification), each against an 11-section checklist, with file:line citations throughout. All findings are code-verified (static read); items requiring live UI/API verification are explicitly flagged as such in each module report rather than marked "working." Full detail for every finding summarized here lives in `audit/01-*.md` through `audit/28-*.md` and `audit/98-cross-module-workflows.md` — this report consolidates and prioritizes, it does not repeat their evidence in full.

---

## 1. Overall Production-Readiness Score

| Area | Score /10 | Basis |
|---|---|---|
| Functional completeness | 7 | Core CRUD and lifecycle actions are present and mostly well-built across all 28 modules; several cross-module links are missing (§4) |
| Lifecycle support | 6 | Excellent in places (Modules 5, 12, 19 — real concurrency/transition guards); undermined by two workflows that are structurally broken (Modules 7, 13) and one that bypasses every lifecycle rule (Module 27) |
| Data integrity | 5 | Strong DB constraints where used (Modules 4, 12, 15, 18); recurring "schema models it, write path doesn't populate it" pattern (§5); confirmed schema-vs-code drift on `users.role_id` |
| UX | 7 | Consistent, informative error/success conventions across nearly every module |
| Validation | 8 | Consistently the strongest area of this codebase — thorough, often redundant (servlet + DAO) validation is the norm, not the exception |
| RBAC | 5 | Genuinely excellent architecture (double-layered filter+servlet checks) dragged down by two Critical logic bugs (Module 2) and one confirmed cross-module bypass (Module 26) |
| Security | 3 | **The lowest score in this audit** — a live, actively-used credential checked into source control (Module 22), an AI-driven hard-delete/privilege-escalation path (Module 27), zero CSRF protection app-wide, and the two RBAC logic bugs (Module 2) combine into a genuinely serious security posture despite good practice elsewhere (Modules 4, 12, 21's file-upload handling) |
| API integration | 7 | Consistent conventions; defense-in-depth RBAC re-checks are a recurring strength |
| DB integrity | 6 | Strong where FK constraints are used; the `role_id` documentation drift and several unpopulated-column gaps pull this down |
| Auditability | 7 | Extremely thorough in the best modules (4, 5, 6, 9, 23); some gaps (export actions, Module 11's failure paths) |
| Reliability | 7 | Real production-grade engineering in several modules (row-locking, idempotent retries, graceful partial-failure handling) |
| Performance | 7 | No systemic problems found; a few isolated inefficiencies (Module 4's next-code scan, Module 8's per-request schema introspection) |
| Accessibility | Not assessed | Requires runtime UI audit — out of scope for this code-reading pass across all 28 modules |
| Reporting | 7 | Broad, consistent Excel export coverage (Module 24); one open question (are exports audited) and one mechanical fix needed (formula injection) |

### Overall status: **NOT READY**

This assessment is driven by a small number of genuinely severe, concrete findings rather than broad, systemic incompetence — the majority of this codebase, module by module, is well above what a typical audit of a system this size finds, with real evidence of prior deliberate security-hardening passes (documented in the code's own comments) and multiple modules (14, 19, 20) that would score as production-ready in isolation. But five findings are serious enough, on their own, to block a production go-live for a system managing a real organization's assets: a live leaked SMTP credential actively used by the majority of the app's email traffic (Module 22); an AI assistant that can permanently delete assets and employees through a path that bypasses every safeguard the rest of the application enforces, reachable by a role with no equivalent authority anywhere else in the system (Module 27); two Critical logic bugs that let an Admin seize or sabotage the Super Admin account (Module 2); and a confirmed cross-module RBAC bypass letting any employee browse the full asset and employee directories through search (Module 26). None of these require exotic attacks to exploit — all five are reachable through the application's own intended interfaces by an already-authenticated user.

---

## 2. Critical Blockers (P0)

These must be resolved before any production deployment, in the order that reflects both severity and independence (items 1–2 should happen immediately, regardless of code changes):

1. **[Module 22]** Rotate the Gmail App Password in `WEB-INF/notification.properties` immediately — it is live, checked into source control, and actively used by 41 of ~44 notification-sending call sites.
2. **[Module 2]** Fix the default plaintext credentials in `super_admin_setup.sql`/`seed_data.sql` — rotate any already-deployed instance of these.
3. **[Module 27]** Remove or fundamentally re-scope the AI Copilot's `DELETE_ASSET`/`DELETE_EMPLOYEE` commands — currently perform raw, unguarded `DELETE FROM assets`/`DELETE FROM employees`, a hard-delete capability that exists nowhere else in the application, granted to ASSET_MANAGER for assets (a role with no equivalent authority through any other interface).
4. **[Module 2]** Add a server-side self-modification guard to `UpdateUserRoleServlet` (an Admin can currently change their own role with no check).
5. **[Module 2]** Fix the Super Admin protection logic in `UpdateUserRoleServlet`/`RoleAssignmentDAO` — currently keyed on the literal username `"super_admin"` rather than the account's actual role.
6. **[Module 7]** Fix the Physical Verification review-status mismatch (`'PENDING'` vs. the schema's actual `'SUBMITTED'` default) — the entire Approve/Reject workflow is currently unreachable, both in the UI and the backend guard.
7. **[Module 26]** Add role gating to Global Search's Asset and Employee result blocks, matching each entity's own dedicated-module access list — currently any authenticated role (including EMPLOYEE) can browse the full asset register and employee directory through the search box.
8. **[Module 1/2/3/9 — cross-cutting]** Resolve the `users.role_id` schema-documentation drift: confirm against the actual live/target database schema whether this column exists (strong evidence across ~13 independent code references suggests it does, meaning `schema.sql` itself is the artifact that's wrong) before any fresh install is attempted from the shipped `schema.sql`.
9. **[Module 18]** Fix `UpdateCategoryVendorMappingStatusServlet`'s live `doGet()` state-change vulnerability — the one unfixed instance of a bug class explicitly fixed five times elsewhere in this same codebase.
10. **[Module 1]** Replace the predictable `username+"123"` temporary password formula for newly-generated employee logins.
11. **[Module 22]** Consolidate the two disconnected SMTP-configuration mechanisms so the admin-facing Settings page actually controls real notification traffic (this fix also structurally prevents #1 from recurring).
12. **[Module 23]** Add transactional/rollback safety (or an automatic pre-restore backup) to Database Restore, and confirm Database Backup's table-list scope is actually complete.
13. **[Module 28]** Confirm `TunnelControlServlet`'s process-spawning capability is excluded from the actual production deployment, or formally accept it as a documented exception.

---

## 3. Broken / UI-Only / Partially-Working Actions (Consolidated)

| Module | Control | Status | Root Cause |
|---|---|---|---|
| 7 | Approve/Reject Physical Verification | **BROKEN** (both UI and backend) | `review_status` enum mismatch (`'PENDING'` never occurs) |
| 4 | Live "Asset Code Available?" AJAX check | **BROKEN** (over-restrictive) | Missing `RoleAccessUtil` entry, 403s for every role |
| 18 | Enable/Disable Category-Vendor Mapping via GET | **UI WORKS, BACKEND UNPROTECTED** | Live GET-state-change vulnerability |
| 2 | Change-own-role via `UpdateUserRoleServlet` | **UI WORKS, BACKEND UNPROTECTED** | No self-modification guard server-side |
| 2 | Super Admin role-change protection | **UI WORKS, BACKEND UNPROTECTED** (for any non-literally-named account) | Username-based check instead of role-based |
| 26 | Global Search (Asset/Employee categories) | **UI WORKS, BACKEND UNPROTECTED** | Missing role gate present on sibling categories on the same page |
| 27 | Copilot "delete asset"/"delete employee" | **INCORRECT LOGIC** (works exactly as coded, but the logic itself is wrong for this app) | Raw `DELETE` bypassing every lifecycle safeguard |
| 22 | Notification Settings save | **BACKEND CORRECT, UI MISLEADING** | Settings persist correctly but don't control most real email traffic |
| 13 | Disposal Approval | **NOT IMPLEMENTED** | Schema models a `PENDING/APPROVED` workflow; code hardcodes `COMPLETED` |
| 19 | Asset request → allocation link (`fulfilled_asset_id`) | **NOT IMPLEMENTED** | Column exists, never written |
| 11 | Maintenance request ↔ maintenance log link | **NOT IMPLEMENTED** | No FK either direction |
| 5 | `AssetAllocationDAO.returnAllocation()` | **DUPLICATE / DEAD CODE** | Confirmed zero callers |
| 4 | `AssetDAO.disposeAsset(int)` single-arg overload | **DUPLICATE / DEAD CODE** | Confirmed zero callers |
| 16 | Category `useful_life_years`/`default_depreciation_rate` | **NOT IMPLEMENTED** | Hardcoded at creation, unreachable via any UI action |
| 17 | Vendor `gst_number` | **NOT IMPLEMENTED** | Same pattern, compliance-relevant |

---

## 4. Missing Workflows & Lifecycle Gaps

See [98-cross-module-workflows.md](98-cross-module-workflows.md) for the full trace of all 8 required end-to-end workflows. Summary:

- **No Procurement/Purchase Order/Goods Receipt capability exists at all** — assets simply come into being via manual form entry (Module 4); "Purchase → Receive" is entirely unmodeled.
- **No warranty claims capability** (only renewal) — a reasonable scope choice, not a defect.
- **No accounting/GL integration** — asset disposal has no financial closure step; nothing computes accumulated depreciation or posts a write-off entry anywhere in this codebase.
- **Request → Allocation and Maintenance-Request → Maintenance-Log are each two independently-working halves with no structural link between them** — both are one FK-column-and-one-line-of-code fixes away from being closed.
- **Disposal has no approval workflow** despite the schema being built for one (Module 13).
- **Physical Verification's reconciliation step is completely non-functional** (Module 7) — the most severe single break in any traced workflow.
- Two workflows — **Employee Exit/Retirement (Module 19)** and **Warranty Expiry/Renewal (Module 14)** — work essentially perfectly end-to-end and are worth citing as the standard the rest of the system should be brought up to.

---

## 5. Data-Integrity Risks

The dominant, recurring pattern across this entire audit is: **the database schema correctly models a relationship or attribute, but no code path ever populates it.** Confirmed instances:

| Column/Field | Module | Consequence |
|---|---|---|
| `asset_allocation.issued_by` | 5 | No queryable "who issued this asset" for any allocation made through the live UI |
| `asset_requests.fulfilled_asset_id` | 6 | No link from a fulfilled request to its actual allocation |
| `employees.is_deleted`/`deleted_at`/`deleted_by`/`delete_reason` | 9 | "Deleted" employees are indistinguishable from merely-deactivated ones at the data level |
| `asset_categories.useful_life_years`/`default_depreciation_rate` | 16 | Every category is identical on this dimension, permanently |
| `vendors.gst_number` | 17 | No vendor tax-compliance record ever possible |
| `employees.department_name` (denormalized) | 15 | Write-orphaned, but confirmed likely dead/unread — lower risk than initially flagged |
| `employees.employee_status='TRANSFERRED'` | 19 | Enum value with no confirmed writer — Transfer leaves `employee_status` at `ACTIVE` |
| `maintenance_logs.approved_by` | 10 | Not confirmed populated |

**Other data-integrity findings**:
- `users.role_id` — likely real (≈13 independent code references) but undocumented in `schema.sql`, the single highest-consequence unresolved question in this audit (Modules 1, 2, 3, 9).
- `schema.sql`'s `password_reset_tokens` definition is confirmed stale (legacy shape), self-healed at runtime — direct evidence `schema.sql` is not reliably kept in sync with the application's actual requirements (Module 1).
- `asset_returns.received_by`/`asset_allocation.received_by` can be silently misattributed to `user_id=1` if the free-text `receivedBy` field doesn't match a real username (Module 12) — the exact anti-pattern this codebase's own comments describe fixing in five other places.
- No DB-level immutability enforcement on `audit_logs` — the application never offers a delete path, but nothing confirms the DB grants themselves are locked down (Modules 1, 3).

---

## 6. Security Risks

Ranked by severity:

1. **[Critical]** Live, actively-used SMTP credential in source control (Module 22).
2. **[Critical]** AI Copilot hard-delete/privilege-escalation path (Module 27).
3. **[Critical]** Two Super-Admin-seizure/self-modification RBAC logic bugs (Module 2).
4. **[High]** Global Search cross-module access-control bypass (Module 26).
5. **[High]** Predictable temporary passwords for new employee accounts (Module 1) — defeats forced-password-change protection.
6. **[High]** Database Restore has no rollback safety (Module 23) — an operational-reliability risk more than a classic security one, but severe for a disaster-recovery feature.
7. **[Medium]** Zero CSRF protection anywhere in the application — mitigated in a handful of specific places by incidental factors (re-authentication requirements on Change Password/Emergency Reset, file-upload browser restrictions on Database Restore), but present as a gap on the overwhelming majority of state-changing endpoints across all 28 modules.
8. **[Medium]** One live, unfixed GET-state-change vulnerability remains (Module 18), the exception among six otherwise-fixed instances of the same bug class.
9. **[Medium]** Legacy plaintext/SHA-256 password-authentication fallback still present (Module 1), pending confirmation all accounts are BCrypt-migrated.
10. **[Low-Medium]** Excel/CSV formula-injection risk in exported reports' reflected search terms (Module 24).
11. **[Low-Medium]** Inconsistent PII exposure in the QR public-scan fallback path (Module 8).
12. **[Low]** Weaker content-type trust (client-header-based rather than derived) in the Employee Profile Image upload path relative to the Asset Document upload path's stronger standard (Module 21).
13. **[Low]** Unvalidated `X-Forwarded-For`/`X-Real-IP` trust on the one genuinely public-facing page in the app (Module 8), weakening that page's own forensic scan log.
14. **[Informational]** Root-directory hygiene: ~30 ad-hoc utility `.java`/`.class` scripts, a bundled `maven.zip`, and compiled `.class` files committed directly to the repository root (noted in Phase 0) — not a runtime risk, but worth cleaning up before treating this repository as a production artifact source.

**Notable security strengths, worth preserving and extending**: Module 4's asset QR-token generation (confirmed fixed from a real predictable-token vulnerability), Module 21's Asset Document upload/download (textbook-correct path-traversal and content-type handling — the best in the codebase), Module 1's session-fixation hardening and brute-force lockout, and the consistent double-layered (filter + per-servlet) RBAC architecture used almost everywhere.

---

## 7. RBAC Problems

- **Module 2** — the two Critical logic bugs (self-modification, username-based Super Admin protection) are the most severe RBAC findings in the audit.
- **Module 26** — Global Search's Asset/Employee categories bypass the RBAC correctly enforced by their own dedicated modules (Modules 4, 9).
- **Module 27** — AI Copilot's `ASSET_MANAGER` permission branch over-grants delete-class authority it has nowhere else in the system.
- **Module 2 (systemic)** — the "protected account" pattern (`RoleAssignmentDAO.PROTECTED_ACCOUNTS`, `resolveEffectiveRoleForUser`, `isAssignmentForProtected`) is convention-based (hardcoded literal usernames) rather than data-driven (actual role), fragile by construction across ~5 methods.
- **Module 18** — the one unfixed GET-based state-change is also, structurally, an authorization-timing issue (the action executes before any confirmation).
- **Positive finding**: the large majority of RBAC checks across all 28 modules are correctly, consistently, and often redundantly enforced (filter-level + servlet-level + DAO-level in the best cases — Modules 4, 5, 6, 9, 19, 20), with genuine, repeatedly-demonstrated department-scoping for DEPARTMENT_HEAD actions and real, structural (not just policy-based) ownership checks for EMPLOYEE self-service actions.

---

## 8. API / Backend Issues

- No CSRF protection app-wide (§6).
- Several servlets reimplement inline role checks rather than calling the shared `RoleAccessUtil.hasAccess()` helper (Modules 5, 10) — a maintainability/drift risk, not currently a live bug, but worth consolidating.
- `CopilotCommandExecutor`'s write pipeline reimplements raw SQL rather than calling the application's existing, safer DAO methods (Module 27) — the root cause of Finding 1 in that module, and a pattern worth auditing across the rest of that pipeline's other write commands.
- `MaintenanceRequestDAO.updateMaintenanceRequestStatus()` lacks the transition-guard pattern this codebase otherwise treats as standard practice (Module 11).
- Two dead-code DAO methods confirmed via full-codebase caller search (Modules 4, 5) — low risk, but worth removing to prevent future confusion about which code path is authoritative.

---

## 9. Database Issues

- `schema.sql` is confirmed, in at least two independent instances (`users.role_id`, `password_reset_tokens`'s legacy shape), out of sync with what the application code actually requires — a fresh install from the shipped file alone is a real, unverified risk (Modules 1, 2).
- No dedicated incremental migration history for most schema evolution — `schema.sql` appears hand-maintained as a single file (Phase 0 finding, reconfirmed throughout).
- Several tables lack FK constraints where one would meaningfully help (`employee_role_assignments.user_id` has no FK despite being join-critical and the source of a previously-real staleness bug per Module 2's own code comments; `category_vendor_mapping`/`maintenance_requests.request_status`/`priority` are `VARCHAR` rather than `ENUM`, compensated only by application-layer whitelists).
- Strong counter-examples exist and are worth extending as the model: `asset_returns.allocation_id` UNIQUE constraint (Module 12), `category_vendor_mapping`'s composite UNIQUE (Module 18), `asset_disposal.asset_id` UNIQUE (Module 13) — all provide genuine DB-level backstops beyond application logic.
- Database Backup's actual table-scope completeness is unconfirmed (Module 23) — a potentially significant, currently-unverified gap for disaster recovery.

---

## 10. UX / Accessibility Issues

- Accessibility was not assessed in any module (requires runtime/rendered-DOM inspection, out of scope for this code-reading pass) — flagged uniformly across all 28 modules as a required follow-up before a genuine accessibility sign-off.
- Several modules surface only generic error messages where a specific one would help (duplicate-name rejections in Categories/Vendors, Module 16/17).
- Notification Settings (Module 22) actively misleads administrators about what it controls — the most consequential UX finding in the audit, given its security implications.
- Global Search (Module 26) presents a unified, well-designed interface undermined by its access-control gap — worth noting the UX itself is not the problem.

---

## 11. Reporting Gaps

(Module 24 in full)

- Unconfirmed whether any of the 23 export endpoints write their own audit-log entry — a real gap if absent, given how many reports contain financial/personal data.
- Formula-injection risk in reflected search terms, confirmed in one file, likely present in up to five sibling QR-report exports sharing the same generation pattern.
- No dry-run/preview or large-dataset streaming — not confirmed as a current problem, a forward-looking note only.

---

## 12. Audit / Compliance Gaps

- **Module 3 (Audit Logs)**: the "Audit Trail" page itself is a fixed 500-row recent-activity feed with no date-range or user-scoped search — for real investigative use, an admin must export the entire table and search in Excel.
- Silent-failure-with-no-monitoring on the audit-write path itself (Module 3) — an audit-log outage would go completely unnoticed.
- Disposal (Module 13) records `approved_by`/`approved_date` that represent self-approval, since no genuine second-party review step exists — weakens the compliance value of those columns despite them being technically populated.
- Physical Verification's broken reconciliation step (Module 7) is, at its core, a compliance failure — the module's entire purpose is producing a formally-reviewed audit trail, and it cannot.
- Positive: the best modules in this audit (4, 5, 6, 9, 13, 15, 23) demonstrate genuinely thorough audit-logging discipline, including logging *rejected/blocked* attempts, not just successes — a meaningfully higher bar than most systems of this size achieve.

---

## 13. Recommended Advanced Features (Consolidated, P0–P3)

**P0** (see §2 for the full list — repeated here only where not already itemized): none beyond §2.

**P1**
- Populate `fulfilled_asset_id`/link maintenance requests to their resolving logs (closes two of the cross-module gaps in §4).
- Apply `HtmlEscapeUtil.escape()` to every remaining unescaped-HTML-in-email instance (confirmed in Modules 10, 12, and likely 16/17/18 — worth a single cross-cutting sweep rather than module-by-module fixes).
- Add the `receivedBy` free-text hardening fix (Module 12) — replace with a real user/employee picker.
- Add the transition guard to `MaintenanceRequestDAO.updateMaintenanceRequestStatus()` (Module 11).
- Populate `employees.is_deleted`/`deleted_at`/`deleted_by`/`delete_reason` correctly (Module 9).
- Add `vendors.gst_number` to the Add/Edit Vendor forms (Module 17) — the one P1 item with direct regulatory-compliance relevance.
- Align `UploadEmployeeProfileImageServlet`'s content-type trust to `AssetDocumentUploadUtil`'s stronger standard, and confirm the Employee/Vendor document upload siblings match it too (Module 21).
- MFA/TOTP for SUPER_ADMIN/ADMIN roles (Module 1).
- Explicit `<cookie-config>` (Secure/HttpOnly/SameSite) in `web.xml` (Module 1).
- Add a real disposal approval workflow using the schema that already supports it (Module 13).
- Audit every other Copilot write command for the same "reimplements raw SQL, skips DAO safeguards" risk found in `deleteAsset`/`deleteEmployee` (Module 27).

**P2**
- Bulk asset import/CSV (Module 4).
- Time-boxed dynamic duty assignments using the existing `effective_to` column (Module 2).
- Insurance/policy tracking fields (Modules 4, 14).
- Employee-initiated Cancel Request for asset requests (Module 6).
- Retention/archival strategy for `audit_logs` (Module 3).
- Structured old-value/new-value columns for high-value audit actions, beyond free-text (Modules 1, 2, 3).
- Basic magic-byte/content-sniffing validation on all file uploads, as defense-in-depth beyond extension/header checks (Module 21).

**P3**
- CSRF tokens app-wide (listed once here as the single largest recurring P3-or-higher item; individual modules note it repeatedly, consolidated to avoid 28 duplicate line items).
- Consolidate the redundant `status`/`is_active`-style column pairs found in Employees and Categories.
- Session-list/"active sessions" self-service view (Module 1).
- Auction/Sale disposal-method tracking, if ever needed (Module 13).

---

## 14. Cross-Module Dependencies

The following dependency chains were directly confirmed during this audit and are worth keeping visible for any future refactor:

- **Category-Vendor Mapping (18) → Asset Registry (4)**: an active mapping is a hard precondition for asset creation/edit.
- **Asset Allocation (5) → Asset Returns (12)**: Allocation's return-processing is fully delegated to Module 12's DAO, inheriting both its strengths (three-layer double-return protection) and its one open finding (`receivedBy` misattribution).
- **Employee Transfer/Retirement (19) → Asset Returns (12)**: same delegation relationship, same inherited properties.
- **QR/Barcode (8) ← Assets (4), Allocation (5), Maintenance (10), Disposal (13)**: `QrSnapshotService.syncAssetQuietly()` is called from every module that changes an asset's state, keeping the public-facing snapshot table fresh — a real, working cross-cutting integration.
- **Notifications (22) ← nearly every other module**: 41 files depend on `NotificationHelper`, making Module 22's credential/architecture finding the single highest-blast-radius issue in the audit by caller count.
- **RBAC (2) underpins every module's access-control claims** — the two Critical bugs found there have implications for the trustworthiness of every other module's "RBAC: correct" findings insofar as they all assume the underlying role data is trustworthy.
- **Audit Logs (3) underpins every module's auditability claims** — and shares the `users.role_id` dependency that, if it doesn't exist on the live schema, would degrade attribution across literally every audit entry in the system.
- **Global Search (26) reads across Assets (4) and Employees (9)** without inheriting their access control — the clearest example in this audit of a cross-cutting feature silently diverging from the modules it's built on top of.

---

## 15. Prioritized Roadmap

| Priority | Problem/Feature | Module(s) | Reason | Dependency | Complexity |
|---|---|---|---|---|---|
| P0 | Rotate leaked SMTP credential | 22 | Live, actively-exploitable exposure | None | Trivial (rotate credential) |
| P0 | Fix AI Copilot hard-delete bypass | 27 | Bypasses every lifecycle safeguard; role over-grant | None | Medium (reroute through DAOs or remove intents) |
| P0 | Fix Super Admin self-modification/protection bugs | 2 | Admin can seize/sabotage highest-privileged account | None | Small |
| P0 | Fix Global Search RBAC bypass | 26 | Confirmed PII/data over-exposure | None | Small |
| P0 | Fix Physical Verification review-status mismatch | 7 | Entire module's compliance purpose unmet | None | Trivial (one string/enum fix) |
| P0 | Resolve `users.role_id` schema drift | 1, 2, 3, 9 | Fresh-install risk, attribution risk across the app | Requires live-DB inspection | Small once confirmed |
| P0 | Fix remaining GET-state-change bug | 18 | Live, unfixed instance of an otherwise-closed bug class | None | Trivial |
| P0 | Consolidate SMTP config mechanisms | 22 | Settings page currently non-functional for real traffic | Credential rotation above | Medium |
| P0 | Add Restore transactional safety / verify Backup scope | 23 | Disaster-recovery feature has no rollback safety | None | Medium–Large |
| P0 | Rotate/remove default seed passwords | 2 | Checked-in plaintext credentials | None | Trivial |
| P0 | Gate/remove Tunnel Control from production | 28 | Process-spawning capability shouldn't ship to prod | Deployment/packaging decision | Small |
| P1 | Fix predictable temp-password formula | 1 | Account-takeover path for new employees | None | Small |
| P1 | Link Request→Allocation and MaintenanceRequest→MaintenanceLog | 6, 5, 10, 11 | Two confirmed cross-module structural gaps | Schema change (new FK columns) | Medium |
| P1 | Sweep unescaped-HTML-in-email instances | 10, 12, 16, 17, 18 | Known vulnerability class, inconsistently fixed | None | Small (mechanical) |
| P1 | Fix `receivedBy` free-text misattribution | 12, 19 | Misleading audit attribution | None | Small–Medium |
| P1 | Add Maintenance Request transition guard | 11 | Only ungated approval workflow in the app | None | Small |
| P1 | Populate Employee soft-delete columns | 9 | `is_deleted` never actually set | None | Trivial |
| P1 | Add real Disposal approval workflow | 13 | No maker-checker on an irreversible financial action | Schema already supports it | Medium |
| P1 | Align file-upload content-type validation | 21 | Weaker path exists alongside a stronger one | None | Small |
| P2–P3 | See §13 | Various | Value-add / hardening | Various | Various |

---

## 16. Pre-Deployment Checklist

- [ ] Rotate the SMTP credential in `notification.properties`; remove the file from version control; confirm whether git history needs purging.
- [ ] Resolve all 13 items in §2 (Critical Blockers).
- [ ] Run `DESCRIBE users;` (and equivalently for `password_reset_tokens`, `maintenance_logs`) against the actual target production database and reconcile against `schema.sql`, updating whichever is wrong.
- [ ] Confirm Database Backup's table-list scope covers every table required for a genuine full restore.
- [ ] Perform a real backup→restore round-trip against a disposable test database before trusting the feature in production.
- [ ] Rotate any already-deployed default admin/super-admin credentials that may have originated from `seed_data.sql`/`super_admin_setup.sql`.
- [ ] Confirm `TunnelControlServlet`/`CloudflareTunnelServlet` are excluded from the production build, or formally document the exception.
- [ ] Clean up root-directory hygiene items (ad-hoc scripts, `maven.zip`, compiled `.class` files) before treating the repository as a deployable production artifact source.
- [ ] Confirm every account's `password_crypt` is BCrypt (`SELECT COUNT(*) FROM users WHERE password_crypt NOT LIKE '$2%'`) before removing the legacy plaintext/SHA-256 fallback.
- [ ] Add `<cookie-config>` (Secure/HttpOnly/SameSite) to `web.xml`.

---

## 17. UAT (User Acceptance Testing) Checklist

Drawn from each module's own §10 Test Cases (full detail in the individual module reports) — the highest-value scenarios to manually exercise before sign-off:

- [ ] Log in as each of the 6 roles and confirm dashboard/menu contents match documented access (Modules 1, 25).
- [ ] As ADMIN, attempt to change your own role via `manage_roles.jsp` and via a direct API call — both must be blocked (Module 2, regression-critical).
- [ ] Submit, approve, reject, and fulfill an asset request end-to-end; confirm the resulting allocation (if any) is traceable back to the request (Module 6 — expected to currently reveal the missing link, §4).
- [ ] Schedule a physical verification duty, submit a verification, and attempt to approve/reject it — confirm whether the Approve/Reject buttons appear at all (Module 7, expected to currently fail).
- [ ] As EMPLOYEE, use Global Search for another employee's name and for an asset not allocated to you — confirm whether results appear (Module 26, expected to currently fail).
- [ ] As ASSET_MANAGER, ask the AI Copilot to delete a test asset and complete the confirmation flow — confirm whether it actually gets deleted (Module 27, expected to currently succeed — this should not happen).
- [ ] Full employee lifecycle: create → generate login → allocate assets → transfer department → retire, confirming assets are correctly retained/returned at each step (Modules 9, 19 — expected to work well).
- [ ] Full disposal flow: dispose a test asset, confirm no approval gate exists today, and confirm the asset cannot be un-disposed (Module 13).
- [ ] Trigger a real warranty-expiry alert (seed a near-expiry asset) and a real renewal, confirming the notification fires once and doesn't repeat (Module 14 — expected to work well).
- [ ] Perform a full backup→restore cycle against a non-production database and verify data completeness afterward (Module 23).
- [ ] Upload a document/image to each of Assets, Employees, and Vendors; attempt an oversized file, a disallowed type, and a path-traversal-style filename — confirm rejection in each case (Module 21).

---

## 18. Post-Deployment Monitoring Checklist

- [ ] Alert on any `AuditDAO.log()` failure pattern (currently silent — Module 3) — even a basic log-scrape for `"AuditDAO Error"` would surface an otherwise-invisible outage.
- [ ] Monitor `login_security_attempts` for lockout-threshold spikes (Module 1) as an ongoing brute-force indicator.
- [ ] Track email send failures via `email_logs`/`notification_logs` (Module 22) — especially important immediately after the SMTP-consolidation fix, to confirm the new path is actually delivering.
- [ ] Watch for `asset_qr_scan_logs` entries with `scan_status='INVALID_TOKEN'` clustering from a single source (Module 8) as a possible enumeration/probing signal — noting the underlying IP is spoofable, so treat as a soft signal only.
- [ ] Periodically re-run the "audit trail completeness" checks per module (rejection-path logging, export logging) as new features are added, so the coverage gaps noted in §12 don't silently widen.
- [ ] Monitor database size/growth for `audit_logs`, `asset_qr_scan_logs`, and `maintenance_logs` — the three tables most likely to need a retention/archival strategy first (Module 3).
- [ ] After the AI Copilot fix, monitor `audit_logs` for any residual `DELETE_ASSET`/`DELETE_EMPLOYEE` entries to confirm the fix actually closed the path (Module 27).
- [ ] Track disposal volume/value over time once an approval workflow is added (Module 13), to catch any process regression back toward single-actor disposal.

---

## Closing Note

This audit found a codebase with a genuinely wide quality range — some of the strongest, most carefully-reasoned engineering of its kind (Modules 12, 14, 19, 20, and the Asset Document upload path in Module 21 in particular) sitting alongside a small number of severe, concrete defects that would not survive a determined external or insider threat model. The pattern across nearly every module — extensive, self-aware code comments documenting *why* a prior bug existed and how it was fixed — suggests this system has already been through at least one serious hardening pass, and that the team responsible understands these classes of problems well. The findings in this report are best read as the next iteration of that same process: the credential exposure, the AI-copilot bypass, and the RBAC logic bugs are the highest-priority items precisely because everything around them shows this team is capable of, and has already demonstrated, fixing exactly this kind of issue correctly elsewhere in the same codebase.
