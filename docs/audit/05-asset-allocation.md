# Module 5 Audit — Asset Allocation / Assignment

**Scope:** Assigning assets to employees (`allocation.jsp`/`add_allocation.jsp`/`AddAllocationServlet`/`AssetAllocationDAO`), the return-entry redirect stub (`ReturnAllocationServlet`), and employee-facing views (`employee_assets.jsp`, `view_allocation.jsp`). Full Return processing lives in Module 12; Employee Transfer's asset-retention decision (which reads/writes this same table) is cross-referenced but deep-audited in Module 19.
**Verification layers used:** (a) static code reading — full. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Allocation Register | [allocation.jsp](src/main/webapp/allocation.jsp) | List of all allocations, filters, KPIs, entry point for new allocation/return/export |
| Add Allocation | [add_allocation.jsp](src/main/webapp/add_allocation.jsp) | Bulk-capable form: select employee + one or more assets, allocation date, remarks |
| View Allocation | [view_allocation.jsp](src/main/webapp/view_allocation.jsp) | Single allocation detail |
| My Assets (employee) | [employee_assets.jsp](src/main/webapp/employee_assets.jsp) | Self-service view of assets currently allocated to the logged-in employee |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| E1 | Add Allocation submit (bulk: 1..N assets → 1 employee) | [add_allocation.jsp](src/main/webapp/add_allocation.jsp) form | native POST | `POST /AddAllocationServlet` | [AddAllocationServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/AddAllocationServlet.java:18) | `asset_allocation`, `assets` (status flip), `audit_logs` | employee required, allocation date must be past-or-today ([DateValidationUtil.isPastOrToday](src/main/java/com/mycompany/asset_management_system_ams/AddAllocationServlet.java:93)), per-asset validity check inside the DAO transaction | FE: n/a (server enforced). BE: inline role check (SUPER_ADMIN/ADMIN/ASSET_MANAGER, [AddAllocationServlet.java:42](src/main/java/com/mycompany/asset_management_system_ams/AddAllocationServlet.java:42)) — **note: this servlet does not call the shared `RoleAccessUtil.hasAccess()` helper the way `AddAssetServlet`/`UpdateAssetServlet` do; it re-implements the same three-role check inline.** Currently consistent with `RoleAccessUtil`'s own `assetOps` mapping for `/AddAllocationServlet`, so no live drift, but it is a second, independently-maintained copy of the same rule — a future change to one and not the other would silently diverge | Yes — every rejection reason (unauthorized, no asset selected, invalid employee, invalid date, invalid per-asset selection, DAO-level block) gets its own `ADD_BLOCKED` row, matching Module 4's thorough pattern ([AddAllocationServlet.java:43,59,80,94,124,179](src/main/java/com/mycompany/asset_management_system_ams/AddAllocationServlet.java:43)) | Yes — `sendAllocationEmail` after any successful allocation in the batch ([AddAllocationServlet.java:194](src/main/java/com/mycompany/asset_management_system_ams/AddAllocationServlet.java:194)) | Redirects `?msg=added` (all succeeded) / `?msg=partial` (mixed) / `?error=blocked` (all failed) / `?error=noasset,failed,invaliddate,server` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **Finding (Medium, data integrity): `asset_allocation.issued_by` — a dedicated `int` column with its own FK to `users.user_id` ([schema.sql:11,846](schema.sql:11)) specifically for "who issued this asset" — is never populated by `AssetAllocationDAO.addAllocationAndReturnId()` ([AssetAllocationDAO.java:102-105](src/main/java/com/mycompany/asset_management_system_ams/AssetAllocationDAO.java:102), the INSERT column list omits it entirely), the only method this servlet calls. Every allocation created through the actual UI has `issued_by = NULL` at the row level. This is not a total loss of that information — `AddAllocationServlet` writes "Created by: username" into `audit_logs.action_details` as free text — but any report, join, or UI element that reads `asset_allocation.issued_by` directly (rather than re-parsing audit-log prose) will see NULL for every allocation made through this form. Notably, `CopilotCommandExecutor.java:319`'s own separate raw-SQL allocation path (the AI Copilot's "allocate an asset" tool) *does* correctly populate `issued_by` — meaning the two code paths that perform the identical business operation disagree on whether to fill in this column, and the one actually reachable from the primary UI is the one that doesn't.** |
| E2 | Return (redirect stub) | allocation.jsp row action → [ReturnAllocationServlet](src/main/java/com/mycompany/asset_management_system_ams/ReturnAllocationServlet.java) | native GET | `GET /ReturnAllocationServlet?id=N` | [ReturnAllocationServlet.doGet](src/main/java/com/mycompany/asset_management_system_ams/ReturnAllocationServlet.java:16) | none (pure redirect) | `allocationId` must parse as a positive int | Inline role check: SUPER_ADMIN/ADMIN/ASSET_MANAGER/EMPLOYEE ([ReturnAllocationServlet.java:31](src/main/java/com/mycompany/asset_management_system_ams/ReturnAllocationServlet.java:31)) — notably wider than E1 (includes EMPLOYEE), consistent with an employee being able to initiate returning their own allocated asset | n/a | n/a | `?msg=returnfailed` on any parse/missing-id failure | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | This servlet does no actual return processing — it only forwards to `add_return.jsp?allocationId=N`; the real return transaction lives in Module 12's `AddReturnServlet`/`AssetReturnDAO`, which **does** correctly populate `asset_allocation.received_by` on return ([AssetReturnDAO.java:120](src/main/java/com/mycompany/asset_management_system_ams/AssetReturnDAO.java:120)) — so the `received_by` half of this table's "who did it" attribution is fine; only the `issued_by` half (E1) is missing |
| E3 | View Allocation detail | allocation.jsp row → view_allocation.jsp | native GET | `GET view_allocation.jsp?id=N` | inline JSP | `asset_allocation` (read) | parameterized | `RoleAccessUtil` maps `/view_allocation.jsp` → `commonOps` (any logged-in role — read-only detail view, no ownership scoping needed since it's an internal operational record, not per-user-private data) | n/a | n/a | Not assessed this pass | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | — |
| E4 | Employee "My Assets" list | employee_assets.jsp | page load | `GET employee_assets.jsp` | inline JSP → `AssetAllocationDAO.getAllocationsByEmployeeId` | `asset_allocation` (read, scoped) | n/a | Scoped server-side by the logged-in session's own `employee_id`, not a client-suppliable parameter — confirmed by the DAO method signature taking an `employeeId` the JSP would derive from session, not request; no IDOR surface here (an employee cannot request another employee's allocation list by manipulating a URL parameter, since the query path takes no such parameter) | n/a | n/a | Not assessed | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | — |
| E5 | Employee Transfer-Preference submission (cross-module, reads/writes this table) | employee_transfer_preference.jsp → `SubmitEmployeeTransferPreferenceServlet` | native POST | `POST /SubmitEmployeeTransferPreferenceServlet` | not read in this pass (deep dive belongs to Module 19) | `asset_allocation.employee_transfer_preference/_note/_requested_at` | — | — | — | — | — | Code | Not audited this pass | — | `AssetAllocationDAO.submitEmployeeTransferPreference()` ([AssetAllocationDAO.java:377](src/main/java/com/mycompany/asset_management_system_ams/AssetAllocationDAO.java:377)) has a code comment explicitly documenting that its `WHERE employee_id = ? AND ...` clause is the **real** ownership control preventing an employee from setting a transfer preference on an allocation that isn't theirs, "even if a spoofed allocationId is submitted" — i.e. this method is deliberately written defensively against exactly the IDOR class of bug this audit looks for, a good sign; full trace deferred to Module 19 |

---

## 3. Business Workflow / Lifecycle Check

- **Allocation preconditions, transactionally enforced with row locks**: `addAllocationAndReturnId()` checks `isActiveEmployee()` (`employee_status = 'ACTIVE'`) and `isAvailableAsset()` (`asset_status = 'AVAILABLE'`) **using `SELECT ... FOR UPDATE`** inside the same transaction as the insert ([AssetAllocationDAO.java:95,330,340](src/main/java/com/mycompany/asset_management_system_ams/AssetAllocationDAO.java:95)) — this is genuine, correct concurrency protection: two simultaneous allocation attempts for the same asset cannot both succeed, because the second transaction blocks on the row lock until the first commits (at which point `asset_status` has already flipped to `ALLOCATED` and the second's `isAvailableAsset()` check correctly fails). This is a materially stronger guarantee than an application-level check-then-act pattern without locking, and it's the second module in a row (after Module 4's disposal guard) to show this level of care.
- **Status transition on allocate**: `assets.asset_status` flips `AVAILABLE → ALLOCATED` in the same transaction as the `asset_allocation` insert ([AssetAllocationDAO.java:134](src/main/java/com/mycompany/asset_management_system_ams/AssetAllocationDAO.java:134)) — atomic, no window where an asset could be double-allocated or shown as available while actually allocated.
- **Bulk allocation, partial-failure handling**: `AddAllocationServlet` iterates its asset list, allocating what it can and reporting `msg=added`/`msg=partial`/`error=blocked` depending on the mix of successes/failures ([AddAllocationServlet.java:208-216](src/main/java/com/mycompany/asset_management_system_ams/AddAllocationServlet.java:208)) — each asset's allocation is its own independent transaction inside the DAO (not one giant all-or-nothing transaction across the whole batch), which is a reasonable and clearly-communicated design choice (a batch of 5 assets where 1 is already taken results in 4 successful allocations + 1 audit-logged block, not a full rollback) rather than a defect, but worth confirming the UI actually surfaces *which* asset(s) failed in a partial batch, not just an aggregate "partial" message — flag for runtime UI check.
- **Return path is out of this module's own code** — `ReturnAllocationServlet` (E2) is a thin redirect into Module 12's flow; the actual `RETURNED` transition and `received_by` population happen there, confirmed correctly implemented (§2/E2).
- **Reversibility**: an allocation, once made, can only move forward to `RETURNED` (Module 12) — there is no "cancel/undo allocation" action in this module; correcting a mistaken allocation requires going through the return flow like any other, which is a reasonable and auditable design (no silent deletion of the allocation record).

---

## 4. Data Model Check

`asset_allocation` ([schema.sql:1-26 of the extracted block](schema.sql:1)): `allocation_id, asset_id, employee_id, allocation_date, expected_return_date, return_date, allocation_status (enum: ALLOCATED/RETURNED), issue_condition (enum), issue_location_id, issued_by, received_by, remarks, employee_transfer_preference/_note/_requested_at, created_at, updated_at`. FKs: `asset_id→assets` (RESTRICT), `employee_id→employees` (RESTRICT), `issue_location_id→railway_locations` (SET NULL), `issued_by`/`received_by`→`users` (SET NULL).

- **Confirmed gap**: `issued_by` never populated by the live allocation-creation path (§2/E1) — the column and its FK exist and are correctly designed, the write path just doesn't use them.
- `received_by` correctly populated by the live return path (Module 12) — no gap on that side.
- `expected_return_date` exists but `AddAllocationServlet`/`add_allocation.jsp` (per `AddAllocationServlet.java:75`, `returnDate = ""`, passed as `NULL`) never sets it — every allocation is open-ended with no expected-return date captured at creation, meaning there's no data-driven way to flag "this allocation is overdue for return" without an expected date to compare against (worth checking Module 22/Notifications' "overdue actions" feature for whether it relies on this field — if so, it currently has nothing to work with for allocations, only for other overdue-tracked entities).
- `issue_condition` defaults to `'GOOD'` unconditionally on insert ([AssetAllocationDAO.java:105](src/main/java/com/mycompany/asset_management_system_ams/AssetAllocationDAO.java:105)) — no way to record that an asset was issued already in `DAMAGED`/`NEEDS_REPAIR` condition (e.g. issuing a repaired-but-not-fully-restored item) since the form never collects this value; hardcoded rather than parameterized.
- `employee_transfer_preference`/`_note`/`_requested_at` are a well-targeted, purpose-built addition (per its own migration file's naming) for the Employee Transfer workflow — schema design here is clean and specific rather than overloading an existing generic field.

---

## 5. Status Model Check

- `asset_allocation.allocation_status`: 2-value enum (`ALLOCATED`/`RETURNED`) — simplest possible model, and the only transition (`ALLOCATED → RETURNED`) is guarded both by `AssetAllocationDAO`'s own dead `returnAllocation()` method (unreachable, see §8) and by the live Module 12 path, which independently re-checks the allocation is currently `ALLOCATED` before flipping it (not verified in this pass, flag for Module 12 to confirm the same discipline `AssetAllocationDAO.returnAllocation()` showed is preserved in `AssetReturnDAO`'s actual live path).
- **No impossible-state risk found** in this module's own write paths: an asset cannot be allocated twice simultaneously (row-locked availability check, §3), and the allocation/asset status pair are updated atomically together.

---

## 6. RBAC & Security Check

- **CSRF**: same app-wide gap, no tokens; E1 (bulk allocate) has no re-authentication requirement, consistent with the rest of the app.
- **RBAC enforcement**: E1's role check is correct today but implemented as an independent inline copy of the `assetOps` rule rather than calling the shared `RoleAccessUtil.hasAccess()` helper the way Module 4's servlets do — flagging as a maintainability/drift-risk observation, not a live bug (see §2/E1 finding detail).
- **IDOR**: none found. E4 (My Assets) is server-scoped to the session's own employee identity with no client-suppliable employee parameter; E5's DAO method is explicitly documented and written to re-verify ownership server-side against a potentially-spoofed `allocationId`, rather than trusting the caller.
- **Row-locking as a security-adjacent property**: the `FOR UPDATE` pattern in `addAllocationAndReturnId()` also incidentally closes a potential double-allocation race that could otherwise be abused (e.g. two rapid concurrent requests attempting to allocate the same last-available asset to two different employees) — worth noting as a strength here since it's the kind of race-condition gap this audit's methodology specifically asks to be tested for (see §10).

---

## 7. Audit Log & Data Integrity Check

- Consistent with Module 4's pattern: every rejection path individually audit-logged, not just successes.
- **The `issued_by` gap (§2/E1) is itself a data-integrity finding, not just a missing-feature one**: it means the *authoritative, queryable* record of "who issued this asset" only exists as unstructured text in `audit_logs.action_details`, not as a first-class column on the record it belongs to — any future report or query written directly against `asset_allocation` (bypassing `audit_logs`) will get incomplete/NULL answers to "who issued this."
- No other integrity concerns beyond the app-wide `role_id`/audit-immutability findings already tracked centrally.

---

## 8. Missing Features / Gaps

- **`issued_by` not populated** (§2/E1) — the clearest concrete gap in this module.
- **`AssetAllocationDAO.returnAllocation(int allocationId)` is dead code** — confirmed zero callers anywhere in the codebase (`grep` for `.returnAllocation(` across `src/main/java` and `src/main/webapp` returns nothing). Harmless as-is (unreachable), but worth removing or wiring up, since its presence could mislead a future maintainer into assuming it's the live return path when it is not (and if it were ever wired up as an alternate return entry point, it would itself skip setting `received_by`, reintroducing the same class of gap E1 has for `issued_by`).
- **No expected-return-date capture at allocation time** (§4) — blocks any "overdue return" tracking for this module specifically.
- **No issue-condition capture at allocation time** — always defaults to `GOOD`.
- **No partial-batch failure detail surfaced to the user** confirmed in code for E1's bulk path (flag for runtime UI check — the redirect only carries an aggregate `msg=partial`, with per-asset detail only in the audit log, not necessarily shown back to the operator in the same request).

---

## 9. Advanced Feature Recommendations

- **P0** — Populate `asset_allocation.issued_by` in `AssetAllocationDAO.addAllocationAndReturnId()` from the acting user's session `user_id` (the value is already available in `AddAllocationServlet`, just not threaded through to the DAO call).
- **P1** — Add an expected-return-date field to the Add Allocation form and thread it into `expected_return_date`, enabling overdue-return tracking.
- **P1** — Remove or wire up the dead `returnAllocation()` method to avoid future confusion about which code path is authoritative.
- **P1** — Refactor E1's inline RBAC check to call the shared `RoleAccessUtil.hasAccess()` helper (consistency with Module 4's pattern, removes the drift risk).
- **P2** — Allow issue-condition to be recorded at allocation time instead of always defaulting to `GOOD`.
- **P2** — Surface per-asset success/failure detail back to the operator on a partial-batch allocation, not just an aggregate message.
- **P3** — CSRF tokens (shared app-wide recommendation).

---

## 10. Test Cases

No dedicated `AssetAllocationDAOTest`/`AddAllocationServletTest` found in the Phase-0 test inventory — coverage gap for a module with genuinely nontrivial concurrency-sensitive logic that deserves regression protection.

- [ ] **Functional**: allocating a single available asset to an active employee succeeds, flips `assets.asset_status` to `ALLOCATED`, creates one `asset_allocation` row
- [ ] Bulk allocation of N assets to one employee in a single submission creates N allocation rows and correctly reports `msg=added` when all succeed
- [ ] **Negative/Boundary**: allocating an already-`ALLOCATED` asset fails cleanly with `ADD_BLOCKED` logged, no partial state change
- [ ] Allocating to an `INACTIVE`/soft-deleted employee fails
- [ ] Allocation date in the future is rejected
- [ ] **Regression test for the `issued_by` finding**: after a successful allocation via `AddAllocationServlet`, assert `asset_allocation.issued_by` equals the acting user's `user_id` (expected to currently **fail**)
- [ ] **Concurrency (the key test this module's design specifically invites)**: two threads simultaneously attempt to allocate the *same* available asset to two different employees — assert exactly one succeeds and the other receives a clean `ADD_BLOCKED`/failure, never both succeeding and never a deadlock (validates the `FOR UPDATE` row-locking actually behaves as designed under real concurrent load, not just in single-threaded reasoning)
- [ ] **RBAC**: EMPLOYEE/AUDITOR/DEPARTMENT_HEAD directly POSTing to `AddAllocationServlet` is denied; EMPLOYEE successfully reaching `ReturnAllocationServlet` for their own allocation (by design, per E2's role list) but not for another employee's allocation ID (needs verification in Module 12 where the real return logic lives, since E2 itself does no ownership check — it's a pure redirect)
- [ ] **Security**: direct `curl -X POST /AddAllocationServlet` with a valid ASSET_MANAGER session and no CSRF-equivalent token succeeds (documents the shared CSRF gap)
- [ ] **DB integrity**: confirm `asset_allocation.issued_by`/`received_by` FK constraints correctly `SET NULL` (not error) if the referenced user is ever deleted — matches the schema's `ON DELETE SET NULL` clause
- [ ] **API**: `employee_assets.jsp` cannot be made to show another employee's allocations by any request-parameter manipulation (confirms the server-side session-scoping claim in §2/E4 at runtime, not just by reading the code)

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 8 | Bulk allocation, partial-failure handling, and employee self-service view are all present and coherent |
| Lifecycle support | 7 | Clean allocate→return transition; no expected-return-date capture limits overdue tracking |
| Data integrity | 6 | Confirmed `issued_by` gap; `received_by` and the row-locked availability checks are solid |
| UX | 7 | Consistent redirect/messaging convention; partial-batch detail surfacing not confirmed |
| Validation | 8 | Thorough, matches Module 4's standard |
| RBAC | 7 | Correct today; inline-duplicated rule (E1) is a maintainability risk rather than a live gap |
| Security | 6 | No CSRF (shared gap); otherwise no IDOR, and the transfer-preference method shows deliberate anti-spoofing design |
| API integration | 7 | Consistent servlet conventions |
| DB integrity | 6 | Good FK design undermined by an unpopulated column; dead code in the DAO adds confusion risk |
| Auditability | 8 | Every rejection path individually logged, consistent with Module 4 |
| Reliability | 8 | Genuine, correct concurrency protection via `SELECT ... FOR UPDATE` — a real strength |
| Performance | 7 | No obvious inefficiencies; bulk allocation processes assets in a simple loop, each its own transaction — fine at expected scale |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Covered under Module 24 |

**Overall status: MINOR WORK REQUIRED**

The concurrency engineering in this module (row-locked availability checks) is a genuine highlight of the codebase so far — a real, correctly-implemented defense against a race condition this audit's own methodology specifically calls out to test for. The one concrete defect (`issued_by` never populated on the live path) is a straightforward fix once identified, and the rest of the module is solidly built.
