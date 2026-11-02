# Module 9 Audit — Employees

**Scope:** Employee master-record CRUD, deactivate/soft-delete, profile image. Document upload/download is cross-cutting and deep-audited in Module 21; login-account generation is cross-referenced back to Module 1; Transfer/Retire are deep-audited in Module 19.
**Verification layers used:** (a) static code reading — full for the servlets read. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Employee List | [employees.jsp](src/main/webapp/employees.jsp) | Directory, filters, entry point for all actions below |
| Add Employee | [add_employee.jsp](src/main/webapp/add_employee.jsp) | New employee intake, optional immediate login-account creation |
| Edit Employee | [edit_employee.jsp](src/main/webapp/edit_employee.jsp) | Edit master fields |
| View Employee | [view_employee.jsp](src/main/webapp/view_employee.jsp) | Read-only detail |
| Employee Profile (self) | [employee_profile.jsp](src/main/webapp/employee_profile.jsp) | Employee's own profile view (cross-referenced, Module 20) |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I1 | Add Employee (+ optional immediate login creation) | [add_employee.jsp](src/main/webapp/add_employee.jsp) form | native POST (multipart) | `POST /AddEmployeeServlet` | [AddEmployeeServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/AddEmployeeServlet.java:31) | `employees`, `users` (optional), `audit_logs` | not fully re-traced field-by-field this pass; login-account branch generates username/password and inserts into `users` with **both** `role_id` and `current_role` populated ([AddEmployeeServlet.java:197](src/main/java/com/mycompany/asset_management_system_ams/AddEmployeeServlet.java:197)) | `RoleAccessUtil` maps `/AddEmployeeServlet` → `employeeManageOps` (SUPER_ADMIN/ADMIN/DEPARTMENT_HEAD) | Not fully re-traced, consistent pattern expected | Not fully re-traced | Not assessed this pass | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **This is now the 12th independent reference to `users.role_id`** found across the codebase (after Modules 1-2's count of ~10), here used *alongside* `current_role` in the same INSERT — strong further corroboration that `role_id` is a genuine live column simply undocumented in `schema.sql`, not a runtime-breaking bug (see Module 1/2's original finding; this doesn't change the finding, just raises confidence in which of the two explanations is correct — still recommend confirming against the actual live schema before any fresh install, since `schema.sql` remains provably wrong on this point regardless) |
| I2 | Edit Employee | edit_employee.jsp | native POST | `POST /UpdateEmployeeServlet` | not fully re-traced this pass | `employees`, `audit_logs` | — | `employeeManageOps` | — | — | — | Code | Not fully audited this pass | — | — |
| I3 | Disable (Deactivate) Employee | employees.jsp row action | native **POST** | `POST /DisableEmployeeServlet` | [DisableEmployeeServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/DisableEmployeeServlet.java:27) | `employees`, `audit_logs` | must not already be `INACTIVE` | SUPER_ADMIN/ADMIN/DEPARTMENT_HEAD, with DEPARTMENT_HEAD additionally scoped server-side via `isEmployeeUnderDepartmentHead()` ([DisableEmployeeServlet.java:57-61](src/main/java/com/mycompany/asset_management_system_ams/DisableEmployeeServlet.java:57)) — real department-ownership enforcement, not a UI-only filter | Yes — `DISABLE` with old/new status | Yes | `?access=denied/error=invalid/error=disablefailed/msg=alreadyinactive` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **This servlet's own code comment documents a prior fix**: it used to be a `doGet()` reachable via a plain `<a href>` link with only a client-side `confirm()` dialog — meaning a crawler, link-prefetch, or an `<img>`-style forced GET could have silently deactivated an employee for any logged-in admin/dept-head who merely had the page open. Now correctly POST-only. This is a real, concrete example of a GET-based-state-change (CSRF-adjacent, "confused deputy via prefetch") vulnerability class that was found and fixed in a prior pass — worth checking whether the same class of bug still exists on any other action in this codebase that wasn't part of that specific sweep |
| I4 | Delete (Soft-Delete) Employee | employees.jsp row action | native **POST** | `POST /DeleteEmployeeServlet` | [DeleteEmployeeServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/DeleteEmployeeServlet.java:23) | `employees`, `audit_logs` | Must already be non-`ACTIVE` (deactivate first), zero active allocations, zero pending/approved requests ([EmployeeDAO.getEmployeeDeleteBlockReason](src/main/java/com/mycompany/asset_management_system_ams/EmployeeDAO.java:286)) — three real preconditions, all correctly enforced before allowing the delete | Same as I3 — SUPER_ADMIN/ADMIN/DEPARTMENT_HEAD, DEPARTMENT_HEAD scoped to their own department, confirmed via [DeleteEmployeeServlet.java:84](src/main/java/com/mycompany/asset_management_system_ams/DeleteEmployeeServlet.java:84) | Yes — every rejection reason (not-found, unauthorized, wrong-department, system-blocked, delete-failed) individually logged as `DELETE_BLOCKED`, matching Module 4/5's thorough pattern | Yes, HTML-escaped correctly (the servlet's own comment documents this as a prior fix for the same unescaped-free-text-in-email class of bug found in `DisposeAssetServlet`) | `?error=deleteinvalid/deleteunauthorized/deletewrongdept/deleteblocked/deletefailed` | Code | **PARTIALLY WORKING — see Finding 1** | **Medium** | **This is also documented as a prior GET→POST CSRF-adjacent fix, same class as I3.** |

### Finding 1 (Medium, data integrity) — "Delete" never actually populates the dedicated soft-delete columns it was named for

`employees` has a full dedicated soft-delete column set: `is_deleted (tinyint)`, `deleted_at (timestamp)`, `deleted_by (int)`, `delete_reason (varchar)` ([schema.sql:460-463](schema.sql:460)). `DeleteEmployeeServlet` builds a specific, informative `deleteReason` string and passes both it and the acting `deletedByUserId` into `EmployeeDAO.deleteEmployeePermanently(employeeId, deletedByUserId, deleteReason)` ([DeleteEmployeeServlet.java:126](src/main/java/com/mycompany/asset_management_system_ams/DeleteEmployeeServlet.java:126)) — but the method's actual implementation is:

```sql
UPDATE employees SET employee_status = 'INACTIVE', status = 'INACTIVE' WHERE employee_id = ? AND employee_status <> 'ACTIVE'
```

([EmployeeDAO.java:318-319](src/main/java/com/mycompany/asset_management_system_ams/EmployeeDAO.java:318)) — **both the `deletedByUserId` and `deleteReason` parameters are accepted but never referenced anywhere in the method body, and `is_deleted`/`deleted_at`/`deleted_by`/`delete_reason` are never written.** The net effect of "deleting" an employee through this servlet is functionally identical to disabling them a second time (`employee_status`/`status` were most likely already `'INACTIVE'` from the required prior deactivation step) — no row is distinguishably marked as deleted versus merely deactivated, and the specific reason for the deletion the servlet took care to compose is silently discarded. This matters concretely: other code paths in the codebase (Module 2's `getAssignableEmployeesForDropdown`, Module 6's `AddAssetRequestServlet`) filter on `e.is_deleted = 0` specifically to distinguish "genuinely removed" from "temporarily deactivated" employees — since `is_deleted` never actually becomes `1`, those filters can never distinguish the two states either, even though the UI/audit-log language ("removed from active employee directory," "soft-deleted for historical integrity") clearly communicates that distinction is meant to exist. This is the third instance in this audit series of the same pattern (Module 5's `issued_by`, Module 6's `fulfilled_asset_id`): the schema and the surrounding code's own naming/comments describe a specific data model, but the actual write path doesn't populate the columns that model depends on.

---

## 3. Business Workflow / Lifecycle Check

- **Deactivate → Delete is a correctly enforced two-step process**: `getEmployeeDeleteBlockReason()` explicitly requires the employee to already be non-`ACTIVE` before delete is even attempted ([EmployeeDAO.java:293-295](src/main/java/com/mycompany/asset_management_system_ams/EmployeeDAO.java:293)) — you cannot delete an active employee in one action, must deactivate first. Sensible friction against an accidental single-click removal of someone still actively employed.
- **Delete preconditions are genuinely protective**: blocks on active allocations and pending/approved requests, mirroring the same "can't remove something with live dependent state" pattern already seen for Asset disposal (Module 4) and mirrored here for people — good consistency of design philosophy across the codebase.
- **`employee_status` (4-value: `ACTIVE/INACTIVE/TRANSFERRED/RETIRED`) vs. `status` (2-value: `ACTIVE/INACTIVE`) — two overlapping status columns on the same table.** Both are written together by every servlet read this pass (Disable, Delete both set both columns to the same simplified value), but `employee_status` alone carries the richer `TRANSFERRED`/`RETIRED` states used elsewhere (Module 19's Transfer/Retire workflow, not deep-audited this pass) — meaning `status` is a narrower, seemingly redundant shadow of part of `employee_status`'s range. Not confirmed this pass whether any code reads `status` in a context where it would disagree with `employee_status` (e.g., a `RETIRED` employee would have `employee_status='RETIRED'` but `status` would presumably remain stuck at whatever it last was, likely `'INACTIVE'` if retirement logic follows the same dual-write pattern, or `'ACTIVE'` if it doesn't — this needs Module 19 to resolve definitively).

---

## 4. Data Model Check

`employees` ([schema.sql:446-474](schema.sql:446)): `employee_id, employee_code, employee_name, designation, email, phone, department_id, division_id, location_id, user_id, joining_date, employee_status (enum4), status (enum2), is_deleted, deleted_at, deleted_by, delete_reason, created_at, updated_at, department_name`.

- **Finding 1** (above) is the headline data-integrity issue: `is_deleted`/`deleted_at`/`deleted_by`/`delete_reason` are schema-present, referenced by other modules' read queries, but never written by the one servlet whose job is to populate them.
- **Redundant `department_name` column directly on `employees`** ([schema.sql:466](schema.sql:466)) alongside the normalized `department_id` FK — a denormalized cache column; not itself a defect if kept in sync on department rename, but a risk if any department-rename path (Module 15) forgets to also update this column on every affected employee row, silently drifting from the authoritative `departments.department_name`. Flagged for Module 15 to confirm.
- `uk_employees_user_id` UNIQUE KEY correctly enforces the one-employee-to-one-login invariant at the DB layer, not just application logic — good, matches the intent of `GenerateEmployeeLoginServlet`'s (Module 1) own "employee already has a login account" application-level check with a real DB backstop.

---

## 5. Status Model Check

- `employee_status`: 4 values, `TRANSFERRED`/`RETIRED` presumably driven by Module 19's workflow (not confirmed this pass).
- `status`: narrower 2-value shadow of the above, written in lockstep by the two servlets audited here but of unconfirmed behavior under Transfer/Retire.
- **`is_deleted` is a dead column from this module's write path** (Finding 1) — a `0`/`1` flag with `0` as its only ever-reachable value through the code read this pass.

---

## 6. RBAC & Security Check

- **CSRF/GET-state-change class of bug**: both I3 and I4 carry explicit code-comment evidence of a **previously real, previously exploitable vulnerability** (state-changing action reachable via plain GET, protected only by a client-side `confirm()` dialog) that has since been fixed to require POST. This is valuable corroborating evidence for the app-wide CSRF finding already tracked since Module 1: even with these two now correctly POST-only, the app still has zero CSRF tokens, so a malicious page that auto-submits a POST form (rather than relying on a bare `<img>`/GET) would still succeed today — the fix closed the *accidental* trigger vector (crawlers, prefetch, stray links) but not the *deliberate* one (a crafted cross-site auto-submitting form).
- **RBAC enforcement**: consistently correct and department-scoped for DEPARTMENT_HEAD across both Disable and Delete, matching the established pattern from Module 2's `RoleAssignmentServlet`.
- **IDOR**: none found — `employeeId` flows through parameterized queries with correct department-ownership re-verification for the one role (DEPARTMENT_HEAD) that needs scoping.

---

## 7. Audit Log & Data Integrity Check

- Delete's rejection-path audit logging is exemplary — every one of the 5 distinct block reasons gets its own `DELETE_BLOCKED` entry, consistent with the codebase's best modules (4, 5, 6).
- **Finding 1 is itself the primary data-integrity issue for this module.**
- Email notifications correctly HTML-escape free-text fields (documented prior fix, referencing the same class of bug already found and fixed in `DisposeAssetServlet` — good sign of a systematic sweep having been done for this specific vulnerability class across multiple modules, though not exhaustively confirmed for every module in this audit series yet).

---

## 8. Missing Features / Gaps

- **Finding 1**: soft-delete metadata columns unpopulated.
- Two overlapping status columns (`employee_status`/`status`) with unclear authoritative-vs-shadow relationship, not fully resolved this pass — recommend Module 15/19 follow-up or a dedicated schema-cleanup review.
- `department_name` denormalization risk (§4) — needs Module 15 cross-check.
- No visible "restore/undelete" action — if `is_deleted` were ever correctly wired up, there's no reverse path found in this pass (may be intentional).

---

## 9. Advanced Feature Recommendations

- **P0** — Fix Finding 1: have `deleteEmployeePermanently()` actually set `is_deleted=1, deleted_at=NOW(), deleted_by=?, delete_reason=?` using the parameters it already receives and currently discards.
- **P1** — Resolve the `employee_status`/`status` column overlap — either retire `status` in favor of `employee_status` everywhere, or clearly document which one is authoritative for which purpose, and confirm Module 19's Transfer/Retire path keeps both consistent.
- **P1** — Audit the rest of the codebase for any other remaining GET-based state-change action that wasn't part of the sweep that fixed I3/I4's prior vulnerability (a good target list: anything still using `doGet()` for a servlet whose name suggests a mutation).
- **P2** — Confirm `department_name` denormalization is correctly kept in sync on every department rename.
- **P3** — CSRF tokens (shared app-wide recommendation) — would close the remaining deliberate-attack half of the class of bug I3/I4 already partially fixed.

---

## 10. Test Cases

[EmployeeModuleSecurityTest.java](src/test/java/com/mycompany/asset_management_system_ams/EmployeeModuleSecurityTest.java) exists per the Phase-0 inventory — not yet read in full this pass; flag to confirm its actual coverage against the checklist below in a follow-up pass.

- [ ] **Functional**: deleting an already-deactivated employee with no active allocations/requests succeeds
- [ ] **Regression test for Finding 1**: after a successful delete, assert `is_deleted=1` and `delete_reason` is populated (expected to currently **fail**)
- [ ] **Negative/Boundary**: attempting to delete a still-`ACTIVE` employee is blocked with `deleteblocked`
- [ ] Attempting to delete an employee with an active allocation or pending/approved request is blocked, with the specific reason correctly identified
- [ ] **RBAC**: DEPARTMENT_HEAD cannot disable/delete an employee outside their own department (confirmed enforced server-side, not just UI-filtered)
- [ ] EMPLOYEE/AUDITOR/ASSET_MANAGER cannot reach either servlet
- [ ] **Regression test for the fixed GET-state-change bug**: a plain `GET /DisableEmployeeServlet?id=N` (no POST) does not deactivate the employee (this should currently **pass** — confirms the fix holds)
- [ ] **Security**: direct `curl -X POST /DeleteEmployeeServlet` with a valid ADMIN session and no CSRF-equivalent token succeeds (documents the remaining, not-yet-closed half of the CSRF gap)
- [ ] **DB integrity**: `uk_employees_user_id` prevents two employee rows from ever pointing at the same `user_id`

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 7 | Core lifecycle actions present and well-guarded; Add/Edit not fully re-traced this pass |
| Lifecycle support | 7 | Deactivate-before-delete friction and dependent-record blocking are genuinely good design |
| Data integrity | 5 | Finding 1's unpopulated soft-delete columns undermine the very distinction the schema was built to support |
| UX | 7 | Clear, specific error codes per rejection reason |
| Validation | 7 | Strong precondition checks on delete |
| RBAC | 8 | Correct, consistent, department-scoped |
| Security | 6 | Concrete evidence of a real, previously-exploitable GET-state-change bug having been found and fixed — a good sign for this specific class, but the app-wide CSRF gap remains |
| API integration | 7 | Consistent conventions |
| DB integrity | 6 | Good UNIQUE constraints; the `is_deleted`/status-column overlap issues drag this down |
| Auditability | 8 | Thorough rejection-path logging, consistent with the codebase's strongest modules |
| Reliability | 7 | Defensive coding throughout |
| Performance | 7 | No inefficiencies observed |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Covered under Module 24 |

**Overall status: MINOR WORK REQUIRED**

Solid module with real evidence of prior security hardening (the GET→POST fix on Disable/Delete is a genuine, well-documented vulnerability closure) and strong lifecycle guards. The recurring "schema models it, write path doesn't populate it" pattern shows up again here (Finding 1) — by this point in the audit, this looks like a systemic development-process gap worth calling out explicitly in the final report rather than treating each instance as an isolated bug.
