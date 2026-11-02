# Module 10 Audit — Maintenance

**Scope:** Maintenance log creation and update/resolution (`AddMaintenanceServlet`, `UpdateMaintenanceServlet`, `MaintenanceLogDAO`). Employee-initiated maintenance *requests* (a separate upstream workflow) are deep-audited in Module 11.
**Verification layers used:** (a) static code reading — full. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Maintenance Register | [maintenance.jsp](src/main/webapp/maintenance.jsp) | List/filter, entry point for all actions |
| Add Maintenance | [add_maintenance.jsp](src/main/webapp/add_maintenance.jsp) | Log a new maintenance event |
| Edit / Resolve Maintenance | [edit_maintenance.jsp](src/main/webapp/edit_maintenance.jsp), [resolve_maintenance.jsp](src/main/webapp/resolve_maintenance.jsp) | Update/complete an existing record |
| Schedule Service | [schedule_service.jsp](src/main/webapp/schedule_service.jsp) | Preventive-maintenance scheduling (not deep-audited this pass) |
| Maintenance History | [maintenance_history.jsp](src/main/webapp/maintenance_history.jsp) | Read-only history view |
| View Maintenance | [view_maintenance.jsp](src/main/webapp/view_maintenance.jsp) | Single record detail |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| J1 | Add Maintenance | [add_maintenance.jsp](src/main/webapp/add_maintenance.jsp) form | native POST | `POST /AddMaintenanceServlet` | [AddMaintenanceServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/AddMaintenanceServlet.java:16) | `maintenance_logs`, `assets` (status), `audit_logs` | asset required, date past-or-today, recognized maintenance type, cost ≥ 0, description + performed-by required | `isMaintenanceManager(role)` — SUPER_ADMIN/ADMIN/ASSET_MANAGER, matches `RoleAccessUtil`'s `assetOps` mapping (explicitly commented in `RoleAccessUtil.java:342` as "own gate: isMaintenanceManager(role)" — confirmed drift-free) | Yes — thorough per-rejection-reason `ADD_BLOCKED` logging, matching Modules 4-5's standard | Yes — `sendMaintenanceEmail` | `?error=failed/invaliddate/invalidcost` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **Finding 1 (Medium, security): the notification email body embeds the `description` field completely unescaped — `"<tr><th>Description:</th><td>" + description + "</td></tr>"` ([AddMaintenanceServlet.java:275](src/main/java/com/mycompany/asset_management_system_ams/AddMaintenanceServlet.java:275)) — no call to `HtmlEscapeUtil.escape()` anywhere in this servlet, despite that exact utility existing in the codebase specifically to fix this class of bug (per Module 9's `DeleteEmployeeServlet`, whose own code comment cites this as a previously-fixed vulnerability pattern "same class of finding already fixed in DisposeAssetServlet"). Free text describing a maintenance issue is plausibly attacker- or mistake-influenced (an employee-submitted maintenance request description, if this module's `description` value ever originates from Module 11's employee-submitted text — not fully confirmed this pass but a realistic path) and would render unescaped HTML/script in any HTML-capable email client viewing the resulting notification.** |
| J2 | Update / Resolve Maintenance | [edit_maintenance.jsp](src/main/webapp/edit_maintenance.jsp)/[resolve_maintenance.jsp](src/main/webapp/resolve_maintenance.jsp) form | native POST | `POST /UpdateMaintenanceServlet` | [UpdateMaintenanceServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/UpdateMaintenanceServlet.java:22) | `maintenance_logs`, `assets` (status), `audit_logs` | required fields, date not in future, `nextDueDate` not before `maintenanceDate` | SUPER_ADMIN/ADMIN/ASSET_MANAGER, inline check ([UpdateMaintenanceServlet.java:48](src/main/java/com/mycompany/asset_management_system_ams/UpdateMaintenanceServlet.java:48)) — same inline-duplicate-rather-than-shared-helper pattern noted in Module 5 | Yes — `UPDATE`/`UPDATE_FAILED` | Yes — completion-specific notification when status transitions to `COMPLETED`/`RESOLVED` ([UpdateMaintenanceServlet.java:151-182](src/main/java/com/mycompany/asset_management_system_ams/UpdateMaintenanceServlet.java:151)), correctly gated on an actual status *change* (`!maintenanceStatus.equalsIgnoreCase(oldStatus)`) rather than firing on every save regardless of whether anything changed — a genuinely nice touch not seen consistently elsewhere in this codebase | `?error=failed/invaliddate` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **Same Finding 1 pattern recurs here**: `"<tr><th>Work Done:</th><td>" + workDone + "</td></tr>"` ([UpdateMaintenanceServlet.java:157](src/main/java/com/mycompany/asset_management_system_ams/UpdateMaintenanceServlet.java:157)) is unescaped. **No explicit guard prevents re-editing an already-`COMPLETED` maintenance record** (unlike Module 7's duty-lock pattern) — this may be intentional (allowing an ops-role user to correct a mistake in a closed record) rather than a defect, since the action is restricted to trusted ops roles, not open to the original requester; flagged as a design observation, not a confirmed bug |

---

## 3. Business Workflow / Lifecycle Check

- **Genuinely strong concurrency/consistency engineering, consistent with the codebase's best modules**: `MaintenanceLogDAO.addMaintenanceLogAndReturnId()` locks the asset row with `SELECT asset_status FROM assets WHERE asset_id = ? FOR UPDATE` before deciding anything ([MaintenanceLogDAO.java:120-123](src/main/java/com/mycompany/asset_management_system_ams/MaintenanceLogDAO.java:120)), blocks adding maintenance to a `DISPOSED` asset at **two independent layers** (the row-locked pre-check, and a second `WHERE asset_status <> 'DISPOSED'` guard on the asset-status `UPDATE` itself, [MaintenanceLogDAO.java:136-139,309-312](src/main/java/com/mycompany/asset_management_system_ams/MaintenanceLogDAO.java:136)), and commits the maintenance-log insert and the asset-status update together in one transaction — a disposed asset cannot silently regain a maintenance history entry or have its status incoherently changed underneath a disposal.
- **Same schema-adaptive `columnExists()` defensive pattern seen in Module 7** — `maintenance_logs` apparently carries columns beyond what `schema.sql` documents (`description`, `performed_by` were checked for existence and conditionally included, but are not present in the base `CREATE TABLE maintenance_logs` definition in `schema.sql`, [schema.sql:510-533](schema.sql:510) — only `issue_reported`/`work_done` are). Unlike Module 7's `review_status`/`'PENDING'` bug, this module's defensive coding correctly *degrades gracefully* here rather than silently breaking — a genuine positive contrast worth noting: the same defensive pattern, applied correctly, prevents rather than causes a schema-drift failure.
- **Asset status mapping on completion**: `resolveAssetStatusAfterMaintenance()` drives `condition_status`/`service_status` consistently with the chosen outcome — not fully re-traced line-by-line this pass, but the overall shape mirrors Module 7's (well-designed) status-mapping approach.
- `maintenance_logs.approved_by` exists in the schema ([schema.sql:522](schema.sql:522)) but was not observed being populated by either servlet read this pass — possible further instance of the "schema models it, write path doesn't" pattern (Modules 5/6/9), not confirmed with full certainty this pass since the DAO's dynamic column-list construction wasn't traced for every column.

---

## 4. Data Model Check

`maintenance_logs` ([schema.sql:510-533](schema.sql:510)): `maintenance_id, asset_id, maintenance_type (enum), maintenance_date, next_due_date, issue_reported, work_done, maintenance_status (enum), cost, vendor_id, performed_by_employee_id, approved_by, remarks, created_at, updated_at` — plus at least `description`/`performed_by` (free-text) columns confirmed live via the code's own `columnExists()` checks but absent from `schema.sql`'s definition, corroborating the recurring schema-documentation-drift finding from Modules 1/2/3/9.

- `vendor_id`/`performed_by_employee_id` give a choice between an external vendor and an internal employee having performed the work — sensible for a real maintenance operation; not confirmed this pass whether the UI correctly enforces "pick one" vs. allowing both/neither to be set inconsistently with the free-text `performed_by` field also being collected (potential redundant/conflicting "who did this" representation, similar in spirit to Module 9's dual status columns — worth a follow-up check).
- `next_due_date` exists and is validated (must not precede `maintenance_date`) but `addMaintenanceLogAndReturnId()`'s insert explicitly sets it to `null` unconditionally ([MaintenanceLogDAO.java:182-185](src/main/java/com/mycompany/asset_management_system_ams/MaintenanceLogDAO.java:182)) — meaning a next-due-date can only ever be set via the *Update* path (`UpdateMaintenanceServlet` does collect and validate `nextDueDate`), never at creation time, even though the Add form doesn't appear to be prevented from collecting one. If `add_maintenance.jsp` has a next-due-date field the user can fill in, it is silently discarded — worth a runtime UI check to confirm whether that field exists on the Add form and is misleadingly accepted-then-ignored.

---

## 5. Status Model Check

- `maintenance_status`: 4-value enum (`OPEN/IN_PROGRESS/COMPLETED/CANCELLED`) — `addMaintenanceLogAndReturnId()` derives the initial status from the *asset* outcome status rather than accepting it directly (`AVAILABLE→COMPLETED`, anything else→`IN_PROGRESS`, [MaintenanceLogDAO.java:172-180](src/main/java/com/mycompany/asset_management_system_ams/MaintenanceLogDAO.java:172)) — a reasonable simplification, though it means `CANCELLED` and a direct `OPEN` state are not reachable from the creation path at all (only via a subsequent Update).
- **No re-completion guard**, as noted in J2 — worth explicit product-decision confirmation (intentional correctability vs. an oversight) rather than treating as a defect outright, given this codebase's demonstrated pattern of deliberately guarding similar transitions elsewhere (Modules 6, 7) when the intent was to lock them.

---

## 6. RBAC & Security Check

- **Finding 1** (above) is this module's primary security-relevant finding: unescaped free text in HTML email bodies, recurring in both servlets, inconsistent with a fix already applied elsewhere in the same codebase for the identical vulnerability class.
- **CSRF**: app-wide gap applies.
- **RBAC enforcement**: correct and consistent, confirmed drift-free against `RoleAccessUtil`'s own explanatory comment for this specific module.
- **Concurrency protection**: genuinely strong (`FOR UPDATE` row-locking), consistent with this codebase's best work (Modules 5, 6).

---

## 7. Audit Log & Data Integrity Check

- Add's rejection-path logging is thorough (matches Modules 4-6's standard); Update logs both success and failure outcomes.
- Transactional integrity between the maintenance-log insert and the asset-status update is solid — no window where one could succeed without the other.
- `approved_by` possibly unpopulated (§3) — flagged for follow-up, not confirmed with full certainty this pass.

---

## 8. Missing Features / Gaps

- **Finding 1**: unescaped HTML-email injection risk, present in both Add and Update paths.
- `next_due_date` silently discarded at creation time even if collected on the Add form (needs runtime UI confirmation).
- No re-completion lock on a `COMPLETED` record (may be intentional).
- Possible redundant "who performed this" representation (`performed_by_employee_id` FK vs. free-text `performed_by`) not fully resolved this pass.
- `approved_by` possibly never populated.

---

## 9. Advanced Feature Recommendations

- **P0** — Apply `HtmlEscapeUtil.escape()` to `description`/`workDone` (and any other free-text field) before embedding them in HTML email bodies in both `AddMaintenanceServlet` and `UpdateMaintenanceServlet`, matching the fix already applied elsewhere in the codebase — this is a quick, mechanical fix once flagged, and worth grep-auditing the rest of the codebase for any other remaining unescaped-email instances while at it (a good candidate for a dedicated cross-cutting fix pass rather than module-by-module).
- **P1** — Confirm and fix the `next_due_date`-silently-discarded-at-creation gap.
- **P2** — Decide and enforce whether `performed_by_employee_id` and free-text `performed_by` should be mutually exclusive, redundant-but-synced, or genuinely independent (e.g. vendor's free-text contact name vs. internal employee link).
- **P2** — Confirm whether a re-completion lock is wanted for `COMPLETED` records, for consistency with the guard philosophy already applied in Modules 6/7.
- **P3** — Populate `approved_by` if a distinct approval step is intended.
- **P3** — CSRF tokens (shared app-wide recommendation).

---

## 10. Test Cases

No dedicated `MaintenanceLogDAOTest`/`*MaintenanceServletTest` found in the Phase-0 inventory.

- [ ] **Functional**: adding a maintenance log for an `AVAILABLE`-outcome record sets `maintenance_status='COMPLETED'` and the asset back to a serviceable state; a non-`AVAILABLE` outcome sets `IN_PROGRESS` and the asset to the corresponding maintenance status
- [ ] **Negative/Boundary**: adding maintenance to a `DISPOSED` asset is blocked (both the pre-check and the UPDATE-layer guard should independently prevent it — test both by attempting to race past the first)
- [ ] Future-dated maintenance date is rejected; `nextDueDate` before `maintenanceDate` is rejected
- [ ] **Regression test for Finding 1**: submit a maintenance description/work-done value containing `<script>` or HTML tags — assert the resulting email body has it escaped (expected to currently **fail**)
- [ ] Completion notification only fires on an actual status *transition* to COMPLETED/RESOLVED, not on every save while already COMPLETED (this appears correctly guarded — confirm as a regression check)
- [ ] **RBAC**: EMPLOYEE/AUDITOR/DEPARTMENT_HEAD cannot POST to either servlet
- [ ] **Concurrency**: two simultaneous maintenance-add attempts on the same asset where one is racing a disposal — confirm the row lock correctly serializes them and the disposal (if it commits first) prevents the maintenance add, or vice versa depending on ordering, but never both succeed incoherently
- [ ] **Security**: direct `curl -X POST /AddMaintenanceServlet` with a valid ASSET_MANAGER session and no CSRF-equivalent token succeeds (documents the shared CSRF gap)
- [ ] **DB integrity**: confirm `next_due_date` behavior at creation time empirically (resolves the open question in §4)

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 8 | Core log/update/resolve flow is complete and coherent |
| Lifecycle support | 7 | Strong disposal-guard consistency; no re-completion lock (possibly intentional) |
| Data integrity | 6 | Schema-drift columns handled gracefully; possible redundant/unpopulated fields not fully resolved |
| UX | 7 | Clear error codes; completion-only notification is a nice touch |
| Validation | 8 | Thorough, matches the codebase's strongest modules |
| RBAC | 8 | Correct, consistent, explicitly drift-free per its own code comment |
| Security | 5 | Finding 1 (unescaped email HTML) is a real, concrete, recurring gap in this specific module |
| API integration | 7 | Consistent conventions |
| DB integrity | 7 | Good transactional discipline; minor unresolved column-population questions |
| Auditability | 7 | Thorough logging on both create and update paths |
| Reliability | 8 | Row-locking and dual-layer disposal guards are a genuine strength |
| Performance | 7 | No inefficiencies observed |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Covered under Module 24 |

**Overall status: MINOR WORK REQUIRED**

The concurrency and transactional engineering in this module is genuinely strong and consistent with the codebase's best work (Modules 4-6). The one concrete, actionable finding — unescaped free text in HTML emails — is a straightforward mechanical fix, but notable because the codebase demonstrably already knows how to fix it (via `HtmlEscapeUtil`) and simply didn't apply that fix here, suggesting the earlier fix pass wasn't systematically swept across every module that builds an HTML email body.
