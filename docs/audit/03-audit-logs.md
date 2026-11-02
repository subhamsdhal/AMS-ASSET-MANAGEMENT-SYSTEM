# Module 3 Audit — Audit Logs

**Scope:** System-wide audit trail — write path (`AuditDAO`, called from every other module) and read paths (`audit_logs.jsp` list view, `view_audit_log.jsp` detail view, `export_audit_logs.jsp` full export).
**Verification layers used:** (a) static code reading — full. (b)/(c) not performed this pass.
**Why this module matters disproportionately**: every other module's "Audit Log Written? Yes" claim in this audit series is only as trustworthy as this module's write path actually being reliable — this module is effectively load-bearing for every prior and future module's §7 findings.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Audit Trail (list) | [audit_logs.jsp](src/main/webapp/audit_logs.jsp) | Latest 500 audit rows, KPI tiles (total/today/exports/blocked), client-side search/filter/sort |
| Audit Log Detail | [view_audit_log.jsp](src/main/webapp/view_audit_log.jsp) | Single `audit_id` detail view |
| Export Audit Logs | [export_audit_logs.jsp](src/main/webapp/export_audit_logs.jsp) | Full, unbounded Excel export of `audit_logs` |

No modals; all three are full-page JSPs. No dedicated "search by user/date range" server-side query exists anywhere in this module — see §2/§8.

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| C1 | View Audit Trail (page load) | [audit_logs.jsp:198-267](src/main/webapp/audit_logs.jsp:198) | page load | none (JSP-embedded query) | inline JSP | `audit_logs` (read) | none | FE: role gate inline (`canViewAudit`, [audit_logs.jsp:178](src/main/webapp/audit_logs.jsp:178)). BE: same JSP is the whole backend; RoleAccessUtil maps `/audit_logs.jsp` → `auditorOps` (SUPER_ADMIN/ADMIN/AUDITOR) — matches | n/a (read-only) | n/a | `error=pageLoadFailed` banner on query exception ([audit_logs.jsp:264-266](src/main/webapp/audit_logs.jsp:264)); empty-state not explicitly checked this pass | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Hardcoded `LIMIT 500`, no pagination/offset ([audit_logs.jsp:232](src/main/webapp/audit_logs.jsp:232)) — see §8 |
| C2 | Search / Action filter / Module filter / Clear (client-side) | audit_logs.jsp JS (`auditSearch`, `auditActionFilter`, `auditModuleFilter`, `clearAuditFilters`) | JS `input`/`change` | none — filters the already-loaded 500-row DOM table client-side, not a server request | n/a | n/a | n/a | n/a | n/a | n/a | n/a | Code | PARTIALLY WORKING (by design) | Low | Filtering only ever operates on the 500 rows already sent to the browser — cannot find/filter anything older than that window; no server-side search endpoint exists for this page |
| C3 | Sort columns (click header) | audit_logs.jsp JS `sortTable()` | JS `onclick` | none | n/a | n/a | n/a | n/a | n/a | n/a | n/a | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Client-side only, same 500-row scope |
| C4 | Export Audit Logs | audit_logs.jsp link → export_audit_logs.jsp:374 | native GET | `GET /export_audit_logs.jsp` | inline JSP, Apache POI | `audit_logs` (read, unbounded) | none | FE/BE role gate identical to C1 ([export_audit_logs.jsp:303-309](src/main/webapp/export_audit_logs.jsp:303)); RoleAccessUtil maps `/export_audit_logs.jsp` → `auditorOps` (deliberately narrower than the generic `reportExportOps`, per the comment at [RoleAccessUtil.java:206-215](src/main/java/com/mycompany/asset_management_system_ams/RoleAccessUtil.java:206) — no ASSET_MANAGER access to audit export, consistent with policy) | Not logged as its own audit event this pass (would need to trace whether `export_audit_logs.jsp` calls `AuditDAO.log` for an `EXPORT` action — not found in the greps run; flag as a gap if confirmed absent) | n/a | Not assessed this pass | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Full table, no `LIMIT`, no date-range parameter — see §8 for the performance implication as the table grows |
| C5 | View Audit Log detail | audit_logs.jsp row link → view_audit_log.jsp | native GET, `?id=`/`?audit_id=` | `GET /view_audit_log.jsp?id=N` | inline JSP | `audit_logs` (read, `WHERE audit_id = ?`) | parameterized query — no SQL injection surface ([view_audit_log.jsp:213](src/main/webapp/view_audit_log.jsp:213)) | Same role gate as C1 ([view_audit_log.jsp:171-183](src/main/webapp/view_audit_log.jsp:171)) | n/a | n/a | Not assessed this pass for a nonexistent `audit_id` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | No IDOR concern — audit visibility is system-wide for the three roles that can reach this page at all, not scoped per-department/user, which is the correct model for a system-wide audit trail |

There is no "Delete Audit Log" control anywhere in the codebase (confirmed by file listing — no `DeleteAudit*` servlet exists) — see §7 for what this does and doesn't guarantee.

---

## 3. Business Workflow / Lifecycle Check

Not an asset-lifecycle module itself — this module is the **evidence layer** underneath every other module's lifecycle transitions. Its own "workflow" is simply: mutating action happens anywhere in the app → `AuditDAO.log(...)` is called inline by that action's own servlet/JSP → row appears here. There is no review/acknowledgment/escalation workflow on top of the raw log (e.g. no "flag this entry for investigation" or "mark reviewed" state) — it's a pure append-and-display trail, not a case-management tool. That's a reasonable scope for this table, but worth noting against §9's Security Information and Event Management (SIEM)-adjacent recommendations.

---

## 4. Data Model Check

`audit_logs`: `audit_id (bigint PK), user_id, username, user_role, module_name, action_type, record_id (varchar), action_details (text), ip_address, user_agent, created_at` ([schema.sql:348-365](schema.sql:348)), indexed on `user_id`, `module_name`, `action_type`, `created_at`.

- **`record_id` is a free `varchar(80)`, not an FK to anything** — by necessity, since a single audit table spans dozens of unrelated source tables (assets, users, employees, etc.) with no polymorphic-association pattern (no paired `record_table`/`record_type` discriminator column separate from `module_name`). `module_name` doubles as that discriminator informally (e.g. `"users"`, `"employee_role_assignments"`), which works but is a soft convention, not enforced — a typo'd `module_name` in some future servlet would silently create an audit entry that's hard to correlate back to its source table programmatically (only human-readable, not queryable-by-join).
- **No structured old-value/new-value columns** — flagged already in Modules 1 and 2; restating here as the authoritative module for this finding since it applies to the table itself, not any one caller. `action_details` is the sole payload, a free-text sentence written ad-hoc by each calling servlet (verified consistent style across ~15 call sites read so far in Modules 1-2, but nothing enforces a machine-parseable format).
- **`getUserAuditInfo()` (the function that resolves `user_id` → `username`/`user_role` for every single log write) depends on `JOIN roles r ON u.role_id = r.role_id`** ([AuditDAO.java:103-107](src/main/java/com/mycompany/asset_management_system_ams/AuditDAO.java:103)) — **the same `users.role_id` schema-drift risk flagged in Modules 1 and 2, but here the blast radius is maximal**: if this specific query fails against the live schema, `getUserAuditInfo()`'s try/catch ([AuditDAO.java:122-124](src/main/java/com/mycompany/asset_management_system_ams/AuditDAO.java:122)) swallows the exception and returns an all-null `UserAuditInfo`, meaning **every audit log row app-wide would be written with `user_id=NULL`, `username=NULL`, `user_role=NULL`** — the entire audit trail would still record *that* something happened and roughly *what* (via `action_details`' free text, which usually embeds the username as a string separately), but would lose the queryable "who" for every row, defeating the point of `audit_logs.user_id`/`user_role` having their own indexed columns at all. Given Module 2's corroborating evidence (`role_id` referenced in seed/setup SQL, strongly suggesting it's a real live column just missing from `schema.sql`'s documentation), this is very likely **not** currently happening in a working deployment — but it is the single highest-consequence unresolved question from the entire audit series so far, and should be the first thing verified (`DESCRIBE users;` against the actual target database) before sign-off.

---

## 5. Status Model Check

Not applicable — `audit_logs` rows have no status/lifecycle of their own (append-only by design, no draft/published/archived states).

---

## 6. RBAC & Security Check

- Consistent 3-role gate (SUPER_ADMIN/ADMIN/AUDITOR) across all three pages, matching `RoleAccessUtil`'s dedicated `auditorOps` entries — no drift found between the pages' own inline checks and the filter map for this specific module (unlike some entries Module 1/2 found drifted elsewhere in the app).
- **No CSRF concern** — all three pages are GET-only / read-only, so CSRF (which targets state-changing requests) doesn't apply here.
- **IDOR**: not applicable in the traditional sense — `view_audit_log.jsp`'s `audit_id` lookup is intentionally global for the roles that can reach it (audit trail is meant to be system-wide for auditors/admins, not per-user-scoped), so an AUDITOR viewing `audit_id=5` that happens to belong to another department is expected behavior, not a vulnerability.
- **Sensitive data exposure**: `audit_logs.action_details` free text has been observed (in Modules 1-2's evidence) to include usernames, IP addresses, user agents, and role names in plain readable form — appropriate for its intended AUDITOR/ADMIN/SUPER_ADMIN-only audience, no over-exposure found. `ip_address`/`user_agent` columns are also directly queryable/exportable — same appropriate audience.
- **Tampering resistance**: no `DELETE`/`UPDATE` endpoint exists in application code for `audit_logs` (confirmed by absence of any matching servlet) — meaning the *application* never offers a way to alter history. This is good practice but is not the same as true immutability: nothing here confirms whether the database user/connection this app uses is restricted from `UPDATE`/`DELETE` at the grant level, or whether a future DAO could add one with no counter-pressure from a DB-level constraint. **Cannot verify DB grants from static code reading** — flag as a required runtime/DBA check.

---

## 7. Audit Log & Data Integrity Check

(This module *is* the audit-log/data-integrity mechanism for the rest of the app — this section instead evaluates the mechanism's own integrity.)

- **Write reliability**: `AuditDAO.log()` is called synchronously, in-line, from within the same request as the action it's logging, generally *after* the primary DB write commits (observed pattern in Modules 1-2: e.g. `ChangePasswordServlet` logs after its `UPDATE`, `EmergencyAdminResetServlet` logs inside the same transaction before `commit()`). This is inconsistent in one respect worth flagging: some callers log *inside* the same transaction as the primary change (so a rollback also undoes the audit row — correct, keeps them atomic) while others (e.g. `LoginServlet`, which has no single enclosing transaction for the whole request) log as a separate, later statement that could independently fail or succeed regardless of whether the "real" action succeeded. Since `AuditDAO.log()`'s own try/catch always swallows its exceptions silently (`System.err.println` only, [AuditDAO.java:49-51,82-84](src/main/java/com/mycompany/asset_management_system_ams/AuditDAO.java:49)), **a failed audit write never surfaces to the calling servlet, never blocks the primary action, and never alerts anyone** — the primary business action always "succeeds" from the user's perspective even if its audit trail silently didn't get written. This is a deliberate and defensible trade-off (an audit-log outage shouldn't halt the whole application), but it does mean audit-log completeness has literally no monitoring or alerting behind it in this codebase — a silent gap in the trail could persist indefinitely unnoticed.
- **No log-write failure metric/alert** — nothing found that counts or surfaces how often `AuditDAO.log()`'s catch block fires; an admin has no way to know "audit logging has been silently broken for the last N hours" without server log access.
- **Immutability**: application-layer only (§6) — no DB-level enforcement confirmed.
- **Completeness**: cannot be fully assessed without cross-referencing every mutating endpoint across all 28 modules against a confirmed `AuditDAO.log()` call — Modules 1-2 found it consistently present on every state-changing servlet read so far, a good sign, but this should be explicitly re-checked as a checklist item in each remaining module's own §7 rather than assumed here.

---

## 8. Missing Features / Gaps

- **No server-side date-range or user-scoped query** on `audit_logs.jsp` — the only way to see "what did user X do last month" is to export the entire table (C4) and filter in Excel, since the main view caps at the most recent 500 rows system-wide (which, in a busy multi-department deployment, could represent well under a day of activity, pushing anything older effectively out of UI reach except via full export).
- **No pagination** — `LIMIT 500` with no offset/page parameter means there is no way to page through history at all from the list view; it is a fixed-size recent-activity feed, not a searchable archive, despite being the page titled "Audit Trail."
- **No export-of-audit-log-export audit entry confirmed** — worth verifying whether exporting the entire audit trail is itself logged (self-referential, but a real compliance expectation: "who downloaded the audit log, and when").
- **No SIEM/webhook integration** — no outbound alerting on suspicious patterns beyond what Module 1 already covers for login-specific events; general audit-log anomalies (e.g. a spike in `DELETE`/`BLOCKED` actions) have no automated detection here.
- **No log-write-failure monitoring**, as noted in §7.
- **No retention/archival policy** implemented in code — an ever-growing single table with no partitioning/archival strategy visible; not urgent at small scale but worth flagging for a system intended for long-term organizational use.

---

## 9. Advanced Feature Recommendations

- **P0** — Resolve the `users.role_id` schema question (shared with Modules 1-2) — this module is the one place where getting it wrong has the widest blast radius (every audit row's "who").
- **P1** — Add server-side filtering by date range and by user/role to `audit_logs.jsp`, with real pagination, so the page lives up to being an actual searchable trail rather than a 500-row recent-activity feed.
- **P1** — Add a lightweight failure counter/alert for `AuditDAO.log()`'s swallowed exceptions (e.g. increment a metric, or degrade to writing a fallback local file) so a broken audit pipeline doesn't fail silently and indefinitely.
- **P2** — Structured old-value/new-value fields (or a JSON payload column) for the highest-value action types (role changes, financial-value changes, status transitions) rather than free text only.
- **P2** — Confirm/enforce DB-level immutability (revoke `UPDATE`/`DELETE` grants on `audit_logs` for the application's DB user, or add an append-only trigger) as defense-in-depth beyond "the app just doesn't offer a delete button."
- **P3** — Retention/archival strategy (partitioning by month/quarter, cold-storage export) once table size becomes a real operational concern.
- **P3** — Basic anomaly detection (e.g. daily digest of `BLOCKED`/`DENIED` spikes) building on the KPI tiles already computed on `audit_logs.jsp`.

---

## 10. Test Cases

No dedicated test file for `AuditDAO` or the audit JSPs was found in `src/test/java/.../*Test.java` (the 13-file inventory from Phase 0 has no `AuditDAOTest`) — **this is a coverage gap** for a component every other module's integrity claims depend on.

- [ ] **Functional**: a known action (e.g. login) produces exactly one new `audit_logs` row with the expected `action_type`/`module_name`/`record_id`
- [ ] `audit_logs.jsp` renders the 4 KPI counts correctly against a known seeded set of rows (total/today/export/blocked)
- [ ] Export produces every row in the table, not just the most recent 500 (regression check distinguishing C1 from C4's query)
- [ ] `view_audit_log.jsp?id=<valid>` renders the correct row; `?id=<nonexistent>` shows a clean not-found state, not a raw exception
- [ ] **RBAC**: EMPLOYEE/ASSET_MANAGER/DEPARTMENT_HEAD directly requesting any of the 3 pages is denied (ASSET_MANAGER specifically, since it's deliberately excluded here unlike most other export endpoints — regression-worthy given `RoleAccessUtil`'s own comment about this being a deliberate narrowing)
- [ ] **Security/regression for §4's finding**: with `AuditDAO.getUserAuditInfo()`'s `JOIN roles r ON u.role_id = r.role_id` forced to fail (e.g. run against a schema.sql-only fresh install), confirm whether audit rows are still written with `user_id`/`username`/`user_role` NULL, and that this failure mode is at least logged server-side (it is, via `System.err.println`) even though it's invisible in-app
- [ ] **DB integrity**: attempt a raw `DELETE FROM audit_logs WHERE ...` and a raw `UPDATE audit_logs SET action_details=...` using the application's own configured DB credentials (not a DBA account) — confirms or refutes whether DB-level immutability exists today (currently unknown per §6)
- [ ] **Concurrency**: two simultaneous actions from different users both produce their own correctly-attributed audit rows with no cross-contamination (tests that `RequestContext`'s per-request IP/UA binding, used by `AuditDAO.log()`, is genuinely request-scoped and not accidentally shared/static)
- [ ] **API**: confirm whether `export_audit_logs.jsp` itself writes an audit entry for the export action

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 5 | Write path is solid and consistently used; read/search path is a fixed 500-row feed, not a real searchable archive |
| Lifecycle support | N/A | Not a lifecycle-bearing module itself |
| Data integrity | 5 | Same `role_id` schema-drift risk as Modules 1-2, here with maximal blast radius if it materializes |
| UX | 6 | Clean KPI/filter/sort UI for what it covers; no date-range/user search is a real functional shortfall for a page titled "Audit Trail" |
| Validation | N/A | Read-only module |
| RBAC | 8 | Clean, consistent 3-role gate across all three pages, matching the central access-control map exactly |
| Security | 6 | No CSRF exposure (read-only), no IDOR, appropriate data exposure to its intended audience; DB-level immutability unverified |
| API integration | 6 | Straightforward JSP-embedded queries, parameterized correctly |
| DB integrity | 6 | Table design is reasonable for a general-purpose free-text audit log; lacks structured diffs and a polymorphic FK-friendly discriminator |
| Auditability | N/A | This module IS the auditability mechanism — see Reliability instead |
| Reliability | 5 | Silent-swallow-on-failure with zero monitoring means the audit trail can go silently incomplete with no operator visibility |
| Performance | 6 | 500-row cap keeps the list view fast; unbounded export could become slow/memory-heavy as the table grows, no pagination/streaming observed |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | 6 | Excel export exists and is appropriately role-gated; no scheduled/automated reporting on audit data |

**Overall status: MINOR WORK REQUIRED**

The write path is the strongest-engineered part of this module (consistent, silent-fail-safe by design) and the read/RBAC layer is clean, but the "Audit Trail" page's lack of real search/date-range/pagination undercuts its usefulness as an actual investigative tool, and the silent-failure-with-no-monitoring pattern means nobody would know if it stopped working. Neither is Critical on its own, but together they mean this module's *availability* as evidence during a real incident is less certain than its consistent write-path usage elsewhere in the app would suggest.
