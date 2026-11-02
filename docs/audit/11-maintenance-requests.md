# Module 11 Audit — Maintenance Requests (Employee-Initiated)

**Scope:** Employee-reported asset issues and the ops-role approve/reject/complete workflow (`EmployeeMaintenanceRequestServlet`, `UpdateMaintenanceRequestStatusServlet`, `MaintenanceRequestDAO`). Distinct from Module 10's direct ops-initiated maintenance logging — this is the upstream "employee reports a problem" intake.
**Verification layers used:** (a) static code reading — full. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Employee Maintenance Request | [employee_maintenance_request.jsp](src/main/webapp/employee_maintenance_request.jsp) | EMPLOYEE-only: report an issue with a currently-allotted asset |
| Maintenance Requests (ops queue) | [maintenance_requests.jsp](src/main/webapp/maintenance_requests.jsp) | Per Module 2's inventory notes, this page **unconditionally redirects every role to `maintenance.jsp`** — its own query/render logic is dead code reached only via that redirect; the actual review queue lives on `maintenance.jsp` itself |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| K1 | Submit Maintenance Request (employee) | [employee_maintenance_request.jsp](src/main/webapp/employee_maintenance_request.jsp) form | native POST | `POST /EmployeeMaintenanceRequestServlet` | [EmployeeMaintenanceRequestServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/EmployeeMaintenanceRequestServlet.java:23) | `maintenance_requests`, `audit_logs` | asset ID must parse, issue description non-empty, priority whitelisted (falls back to `MEDIUM` if not recognized rather than rejecting — a lenient-but-safe default, not a validation hole since it's clamped to a fixed set either way) | BE: role must be exactly `EMPLOYEE` ([EmployeeMaintenanceRequestServlet.java:35](src/main/java/com/mycompany/asset_management_system_ams/EmployeeMaintenanceRequestServlet.java:35)), matches `RoleAccessUtil`'s dedicated EMPLOYEE-only mapping (Module 2's inventory specifically notes this page needed that exact entry to be reachable at all — confirmed consistent) | Yes — `ADD` on success only | Not found in this servlet | `?error=invalid_employee/invalid_asset/empty_desc/not_allotted/submission_failed` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **Real, correctly-implemented IDOR protection**: `dao.isAssetCurrentlyAllottedToEmployee(assetId, employeeId)` ([EmployeeMaintenanceRequestServlet.java:76](src/main/java/com/mycompany/asset_management_system_ams/EmployeeMaintenanceRequestServlet.java:76), backed by a real query against `asset_allocation` requiring `allocation_status='ALLOCATED'` for that specific employee) — an employee cannot report an issue against an asset they don't currently hold, closing off a class of nuisance/spam reports against arbitrary assets. The servlet's own inline comment even labels this "Security check" |
| K2 | Approve / Reject / Complete (ops review) | maintenance.jsp row actions | native POST | `POST /UpdateMaintenanceRequestStatusServlet` | [UpdateMaintenanceRequestStatusServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/UpdateMaintenanceRequestStatusServlet.java:29) | `maintenance_requests`, `audit_logs` | `requestStatus` validated against a 5-value whitelist ([UpdateMaintenanceRequestStatusServlet.java:25-26](src/main/java/com/mycompany/asset_management_system_ams/UpdateMaintenanceRequestStatusServlet.java:25)) — the servlet's own comment documents this as a **prior fix**: before it, an unvalidated status value could permanently strand a request with no action buttons ever appearing again, since `maintenance.jsp`'s button logic only recognizes 4 specific literal values | SUPER_ADMIN/ADMIN/ASSET_MANAGER, matches `assetOps` | Yes — `UPDATE` on success | Not found in this servlet | `?error=invalid_request/empty_status/invalid_status/update_failed` | Code | **CODE LOOKS CORRECT, BUT see Finding 1** | **Medium** | **`MaintenanceRequestDAO.updateMaintenanceRequestStatus()` has no transition-legality guard of any kind** — `UPDATE maintenance_requests SET request_status = ?, remarks = ? WHERE request_id = ?` ([MaintenanceRequestDAO.java:189-190](src/main/java/com/mycompany/asset_management_system_ams/MaintenanceRequestDAO.java:189)) applies unconditionally to any `requestId`, regardless of its current status. Unlike Module 6's `AssetRequestDAO.updateRequestStatus()` (which explicitly guards `PENDING→APPROVED/REJECTED` and `APPROVED→FULFILLED` with a `WHERE request_status = ?` precondition, citing this exact idempotency/concurrency rationale in its own comment) or Module 2's `RoleAssignmentDAO.deactivateAssignment()` (the pattern `AssetRequestDAO`'s comment explicitly credits as its model), this DAO method has no equivalent — a request already `COMPLETED` or `REJECTED` can be freely flipped to any other status by a second action, and two concurrent status-update requests on the same `requestId` would both succeed with no protection against a stale/duplicate/racing action silently re-processing an already-decided request.** |

---

## 3. Business Workflow / Lifecycle Check

### Finding 1 (Medium) — No transition guard on maintenance-request status changes, unlike the equivalent pattern used elsewhere in this same codebase

Restated from §2/K2: this is the one workflow-approval DAO method in the codebase (among the several read across Modules 2, 6, 7, and 11) that does **not** apply the "only transition from an expected current status" guard, despite that exact pattern being established, well-documented, and explicitly cross-referenced between at least three other DAOs (`RoleAssignmentDAO.deactivateAssignment`, `AssetRequestDAO.updateRequestStatus`, and the review-status guard in `ReviewPhysicalVerificationServlet`). Practically:
- Two ASSET_MANAGERs simultaneously acting on the same maintenance request (e.g. one clicking Approve while another clicks Reject, both against a page loaded slightly stale) would both succeed — the second overwrites the first with no warning, unlike the "safe no-op" behavior Module 6 and Module 2 deliberately built for this exact race.
- A `COMPLETED` request could later be moved back to `PENDING` (or any other status) with no restriction, unlike `asset_requests`' careful one-way-only transition model.
- This is not a security vulnerability (both actors in the race are already privileged ops-role users, not an untrusted/lower-privilege actor exploiting anything) — it's a **workflow-integrity gap**, and specifically a *regression* relative to the standard this same codebase has otherwise established for itself.

### Other lifecycle observations

- **`maintenance_requests.jsp`'s unconditional redirect** (per Module 2's inventory notes, confirmed relevant here) means the actual review queue for these requests lives entirely on `maintenance.jsp` — worth confirming during runtime UI check that this doesn't create a confusing double-page situation (a "Maintenance Requests" menu link that immediately bounces to a "Maintenance" page showing a mixed queue of both employee-reported requests and directly-logged maintenance events, which could be a UX ambiguity, not itself a functional defect).
- **No linkage from a completed/approved maintenance *request* to the resulting maintenance *log*** (Module 10) was observed in the schema or code read this pass — `maintenance_requests` has no `maintenance_id`/`resulting_maintenance_id` column, and `maintenance_logs` has no `request_id` back-reference either. This mirrors the exact "schema/code doesn't link the two halves of a workflow" pattern already found in Module 6 (`fulfilled_asset_id` never populated) — here it's more fundamental still, since the column to link them doesn't appear to exist at all, not merely unpopulated. If an ASSET_MANAGER approves an employee's maintenance request and then separately goes and logs the actual maintenance work via Module 10's `AddMaintenanceServlet`, there is no structured way to prove after the fact which maintenance log entry resolved which original request.

---

## 4. Data Model Check

`maintenance_requests` ([schema.sql:902-914](schema.sql:902)): `request_id, asset_id, employee_id, request_date, issue_description, priority (varchar, not enum), request_status (varchar, not enum), remarks, created_at`. FKs to `assets`/`employees` (no `ON DELETE` clause specified, defaults to `RESTRICT` in MySQL/InnoDB — consistent with the rest of the schema's general FK style).

- **Thinner than its sibling table `asset_requests`** (Module 6): no `approved_by`, no `approved_date`/`resolved_at`, no link to the resulting maintenance log. `updateMaintenanceRequestStatus()` doesn't even accept or record an acting-user parameter beyond what `audit_logs` separately captures — the structured, queryable "who approved/rejected/completed this and when" data that `asset_requests.approved_by`/`approved_date` provides for its own workflow simply doesn't exist here at the row level.
- `priority`/`request_status` being plain `VARCHAR` rather than `ENUM` is explicitly flagged by the servlet's own code comment as a known weaker-validation point, compensated for by the application-layer whitelist in `UpdateMaintenanceRequestStatusServlet` — a reasonable compensating control, though it means a direct SQL write (or a future code path that forgets the whitelist) could still write garbage with nothing at the DB layer to stop it.

---

## 5. Status Model Check

- No enum constraint at the DB layer (§4); application-layer whitelist (`PENDING/APPROVED/REJECTED/COMPLETED/IN_PROGRESS`) is the only defense, and unlike Module 6's equivalent, it validates the *value* is one of five allowed strings but does not validate the *transition* is legal from the request's current state (Finding 1).
- **No impossible-state prevention for concurrent/repeated transitions** — this is the concrete, practical consequence of Finding 1.

---

## 6. RBAC & Security Check

- **CSRF**: app-wide gap applies to both actions.
- **RBAC enforcement**: correct and consistent — EMPLOYEE-only for submission, SUPER_ADMIN/ADMIN/ASSET_MANAGER for review, matching `RoleAccessUtil`.
- **IDOR**: K1 is a genuine, well-implemented example of exactly the protection this audit's methodology looks for — real server-side ownership verification against the actual allocation table, not a client-trusted parameter. No IDOR concern found on K2 either (any of the three privileged ops roles acting on any `requestId` is by design, consistent with how Module 6's equivalent approval workflow works).
- **No department-scoping concern** — unlike Module 6's Department Head on-behalf-of gap, this module doesn't give any role an "act on behalf of another employee" capability at creation (an employee can only ever create a request for their own currently-allotted asset), so there's no equivalent finding to carry over here.

---

## 7. Audit Log & Data Integrity Check

- Both success paths are audit-logged; **rejection paths (K1's `not_allotted`/`invalid_asset`/`empty_desc`, K2's `invalid_status`/`empty_status`) are not**, unlike the thorough blocked-attempt logging standard set by Modules 4, 5, 6, and 9. This is a real, if minor, monitoring-coverage gap: an employee repeatedly trying to report issues against assets not allocated to them (a mild abuse-pattern signal) leaves no audit trail today, only a redirect the employee sees and the server-side logs (if any) don't specially flag.
- **Finding 1 is also a data-integrity finding**: without a transition guard, the `audit_logs` history for a given `request_id` could show contradictory/flapping status changes with no application-level explanation of which one should be considered authoritative beyond "whichever wrote last."

---

## 8. Missing Features / Gaps

- **Finding 1**: no transition-legality/idempotency guard on status updates.
- No `approved_by`/`approved_date`/completion-timestamp columns.
- No structured link between a maintenance request and the maintenance log that (presumably) resolves it.
- No audit logging on rejection/validation-failure paths.
- `maintenance_requests.jsp`'s dead-code redirect (cross-referenced from Module 2) — worth a UX/code-cleanup pass, not a functional defect.

---

## 9. Advanced Feature Recommendations

- **P1** — Add the same `WHERE request_status = <expected>` transition guard to `MaintenanceRequestDAO.updateMaintenanceRequestStatus()` that `AssetRequestDAO`/`RoleAssignmentDAO` already establish as this codebase's own standard for exactly this kind of action.
- **P1** — Add `approved_by`/`approved_date`/`completed_at` columns (or equivalent) to `maintenance_requests`, matching `asset_requests`' richer model.
- **P2** — Link a maintenance request to the maintenance log that resolves it (a `maintenance_id` FK on `maintenance_requests`, populated when the corresponding `AddMaintenanceServlet` entry is created for that request).
- **P2** — Log rejection/validation-failure paths to `audit_logs`, matching the standard set elsewhere.
- **P3** — Consider converting `priority`/`request_status` to real DB enums now that the valid-value sets are stable and already enforced at the application layer.
- **P3** — Remove or repurpose `maintenance_requests.jsp`'s dead-code redirect for clarity.
- **P3** — CSRF tokens (shared app-wide recommendation).

---

## 10. Test Cases

No dedicated test file found for this module in the Phase-0 inventory.

- [ ] **Functional**: employee submits a request for a currently-allotted asset — succeeds, status `PENDING`
- [ ] **Negative/Boundary**: employee submits a request for an asset **not** currently allotted to them — blocked with `not_allotted` (this is the module's key protective check — high-value regression target)
- [ ] Invalid/garbage `priority` value falls back to `MEDIUM` rather than being rejected outright (confirm this lenient behavior is intentional, not accidental)
- [ ] Garbage `requestStatus` value on the review side is rejected with `invalid_status` (confirms the documented prior fix holds)
- [ ] **Regression test for Finding 1**: two near-simultaneous status updates on the same `requestId` (e.g. one Approve, one Reject) — assert only one takes effect and the second is a safe no-op (expected to currently **fail** — both currently succeed, last-write-wins)
- [ ] A `COMPLETED` request can currently be moved back to any other status with no restriction — document this as the current (undesired) behavior pending Finding 1's fix
- [ ] **RBAC**: non-EMPLOYEE roles cannot POST to `EmployeeMaintenanceRequestServlet`; EMPLOYEE cannot POST to `UpdateMaintenanceRequestStatusServlet`
- [ ] **Security**: direct `curl -X POST /UpdateMaintenanceRequestStatusServlet` with a valid ASSET_MANAGER session and no CSRF-equivalent token succeeds (documents the shared CSRF gap)
- [ ] **DB integrity**: insert a `maintenance_requests` row directly via SQL with a `request_status` value outside the application's 5-value whitelist — confirm no DB-level constraint stops it (expected to succeed, confirming the enum-vs-varchar gap noted in §4)

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 7 | Core report→review flow works; no linkage to the resulting maintenance log |
| Lifecycle support | 5 | Finding 1's missing transition guard is a real regression relative to this codebase's own established standard |
| Data integrity | 5 | Thinner data model than the analogous `asset_requests` table; VARCHAR status/priority with no DB-level constraint |
| UX | 6 | Clear error codes on the create side; the `maintenance_requests.jsp` dead-redirect is a minor rough edge |
| Validation | 7 | Good input whitelisting on both sides, undermined by the missing transition guard |
| RBAC | 8 | Correct, consistent, no scoping gaps |
| Security | 7 | Genuine, well-implemented IDOR protection on request creation is a real strength; no other issues found beyond the shared CSRF gap |
| API integration | 7 | Consistent conventions |
| DB integrity | 5 | No enum constraints, no approval metadata columns |
| Auditability | 5 | Success-only logging, missing the rejection-path coverage this codebase otherwise does well |
| Reliability | 5 | Finding 1 directly threatens reliability under concurrent ops-role usage |
| Performance | 7 | No inefficiencies observed |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Covered under Module 24 |

**Overall status: MINOR WORK REQUIRED**

The employee-facing intake half of this module (K1) is genuinely well-built, with real IDOR protection that's a credit to the codebase. The ops-review half (K2) is the clear regression point of this module: it's the one workflow-approval action in the entire audit series so far that doesn't apply the transition-guard pattern this same codebase otherwise treats as a matter of course — worth flagging specifically because the fix is a known, proven, three-times-precedented pattern, not a new design problem to solve.
