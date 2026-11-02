# Module 6 Audit — Asset Requests (Employee-Initiated)

**Scope:** Employee (and ops-role-on-behalf-of) asset request creation, and the Approve/Reject/Fulfill workflow (`AddAssetRequestServlet`, `UpdateRequestStatusServlet`, `AssetRequestDAO`).
**Verification layers used:** (a) static code reading — full. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Add Request (ops-role, on behalf of any employee) | [add_request.jsp](src/main/webapp/add_request.jsp) | ADMIN/ASSET_MANAGER/DEPARTMENT_HEAD/SUPER_ADMIN raise a request for a chosen employee |
| Employee Requests (list + self-add) | [employee_requests.jsp](src/main/webapp/employee_requests.jsp) | Employee's own request history + "New Request" entry point |
| New Employee Asset Request | [new_employee_asset_request.jsp](src/main/webapp/new_employee_asset_request.jsp) | Alternate/dashboard-linked entry point for the same self-service create flow |
| Asset Requests (ops review queue) | [asset_requests.jsp](src/main/webapp/asset_requests.jsp) | Approve/Reject/Fulfill queue for ADMIN/ASSET_MANAGER/SUPER_ADMIN |
| View Request | [view_request.jsp](src/main/webapp/view_request.jsp) | Single request detail, shared across employee and ops views |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| F1 | Submit new request (employee self-service) | employee_requests.jsp / new_employee_asset_request.jsp form | native POST | `POST /AddAssetRequestServlet` | [AddAssetRequestServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/AddAssetRequestServlet.java:19) | `asset_requests`, `audit_logs` | category + past-or-today request date + non-empty remarks required | BE: for role EMPLOYEE, `employeeId` is **always** re-derived server-side from the session's own `user_id` via `getLinkedEmployeeId()` ([AddAssetRequestServlet.java:52-59](src/main/java/com/mycompany/asset_management_system_ams/AddAssetRequestServlet.java:52)) — the client-submitted `employeeId` parameter is silently overwritten, not merely validated, so an employee cannot request on another employee's behalf by tampering with the form. Real IDOR protection, not just a UI assumption | Yes — `ADD` on `asset_requests` | Yes — `sendAssetRequestAlert` to the resolved recipient routing (ASSET_MANAGER/DEPARTMENT_HEAD per `NotificationEventService.buildAssetRequestRecipients`) | `?error=invalidselection/invaliddate/failed/server` on employee_requests.jsp or add_request.jsp depending on role; `?success=1` on employee_requests.jsp | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | The underlying `INSERT` (`AssetRequestDAO.addAssetRequestAndReturnId`) additionally re-verifies the employee is `ACTIVE` and not soft-deleted, and the category is `is_active='YES'`, **inside the SQL itself** via a `JOIN ... WHERE e.employee_status='ACTIVE' AND COALESCE(e.is_deleted,0)=0` clause ([AssetRequestDAO.java:64-70](src/main/java/com/mycompany/asset_management_system_ams/AssetRequestDAO.java:64)) — meaning even if the servlet-layer employee/category validity checks were somehow bypassed, the insert itself silently no-ops (0 rows, `generatedRequestId` stays 0) rather than creating a request for an invalid employee/category. Defense-in-depth at the SQL layer, not just the servlet |
| F2 | Submit new request (ops role, on behalf of a chosen employee) | add_request.jsp form | native POST | `POST /AddAssetRequestServlet` | same servlet, non-EMPLOYEE branch | same | same, minus the employee-self-lookup step | BE: role must be SUPER_ADMIN/ADMIN/ASSET_MANAGER/DEPARTMENT_HEAD/EMPLOYEE ([AddAssetRequestServlet.java:41-46](src/main/java/com/mycompany/asset_management_system_ams/AddAssetRequestServlet.java:41)) | same | same | same | Code | **CODE LOOKS CORRECT, BUT see Finding 1 below** | Low-Medium | **For non-EMPLOYEE roles, `employeeId` comes directly from the request parameter with no ownership/department scoping — a DEPARTMENT_HEAD (included in the allowed-role list) can submit a request "on behalf of" any employee system-wide, not just employees in their own department**, unlike the equivalent DEPARTMENT_HEAD-scoping pattern found in Module 2's `RoleAssignmentServlet` (which explicitly re-verifies `isEmployeeUnderDepartmentHead()`). Impact is limited — creating a request only ever produces a `PENDING` row that still needs a separate ASSET_MANAGER/ADMIN/SUPER_ADMIN approval before anything is fulfilled — but it is a real, unscoped cross-department action available to a role this codebase elsewhere treats as department-scoped |
| F3 | Approve / Reject / Fulfill (ops review) | asset_requests.jsp row actions | native POST | `POST /UpdateRequestStatusServlet` | [UpdateRequestStatusServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/UpdateRequestStatusServlet.java:15) | `asset_requests`, `audit_logs` | requestId + a recognized status required | BE: SUPER_ADMIN/ADMIN/ASSET_MANAGER only ([UpdateRequestStatusServlet.java:46](src/main/java/com/mycompany/asset_management_system_ams/UpdateRequestStatusServlet.java:46)) — **deliberately excludes DEPARTMENT_HEAD**, matching `RoleAccessUtil`'s dedicated `requestApprovalOps` mapping and the Phase-0 inventory's own documented "Step 1 decision, DEPARTMENT_HEAD removed" note — confirmed consistent between the servlet, the access-control map, and the design record | Yes — `APPROVED`/`REJECTED`/`FULFILLED`/`UPDATED` action type set per outcome | Yes — status-specific notification with role-aware messaging | `?msg=approved/rejected/fulfilled/updated` or `?error=updatefailed/failed/server` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION, well-designed | — | **`AssetRequestDAO.updateRequestStatus()` enforces legal state transitions server-side with a genuine transition guard** — the `UPDATE` statement's `WHERE` clause requires `request_status='PENDING'` before allowing a transition to `APPROVED`/`REJECTED`, and `request_status='APPROVED'` before allowing `FULFILLED` ([AssetRequestDAO.java:107-132](src/main/java/com/mycompany/asset_management_system_ams/AssetRequestDAO.java:107)) — the code's own comment explicitly frames this as an idempotency/concurrency guard against two admins racing to act on the same request, citing the identical pattern already used in `RoleAssignmentDAO.deactivateAssignment()` (Module 2). A stale/duplicate/racing action becomes a safe no-op (0 rows updated → `updated=false` → `?error=updatefailed`) rather than a silent double-processing or illegal transition. This is the third module in a row to show this exact class of defensive engineering (see Modules 4/5) |
| F4 | View Request detail | view_request.jsp | native GET | `GET view_request.jsp?id=N` | inline JSP | `asset_requests` (read) | parameterized | `RoleAccessUtil` maps `/view_request.jsp` → `allEmployeeOps` (all roles incl. EMPLOYEE) — per Module 2's own inventory note, this entry was previously *missing entirely* (a documented prior fix) since a page every role needs to reach makes no sense restricted to one | n/a | n/a | Not assessed | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **Potential IDOR not resolved in this pass**: since `/view_request.jsp` is open to all authenticated roles including EMPLOYEE with no visible ownership check traced in this pass (the JSP itself was not read in full), it's unconfirmed whether an EMPLOYEE can view another employee's request detail by guessing/incrementing `?id=`. Flagging as **NEEDS RUNTIME VERIFICATION / further code reading** rather than a confirmed finding, since the query itself wasn't traced this pass |

---

## 3. Business Workflow / Lifecycle Check

- **Legal transitions, verified server-side**: `PENDING → APPROVED`, `PENDING → REJECTED`, `APPROVED → FULFILLED` — all three enforced via the conditional `WHERE` clause described in F3, not merely assumed from the UI only presenting valid buttons. This is a genuinely well-implemented lifecycle guard.
- **Finding 2 (Low-Medium) — no guard on the `PENDING` target itself**: `UpdateRequestStatusServlet.normalizeStatus()` silently maps *any* unrecognized `requestStatus` parameter value to `"PENDING"` rather than rejecting the request outright ([UpdateRequestStatusServlet.java:228-237](src/main/java/com/mycompany/asset_management_system_ams/UpdateRequestStatusServlet.java:228)). `AssetRequestDAO.updateRequestStatus()`'s transition guard only applies a `requiredCurrentStatus` precondition when the target is `APPROVED`/`REJECTED`/`FULFILLED` — **when the (possibly-fallback) target is `PENDING`, no current-status precondition is applied at all** ([AssetRequestDAO.java:122-127](src/main/java/com/mycompany/asset_management_system_ams/AssetRequestDAO.java:122)). Combined, this means an ASSET_MANAGER/ADMIN/SUPER_ADMIN POSTing a malformed or unexpected `requestStatus` value (whether by UI bug, tampered request, or a stale/replayed form) would successfully reset an already-`APPROVED`/`REJECTED`/`FULFILLED` request back to `PENDING` with no transition-legality check — the one transition in this workflow that *isn't* guarded is also the one silently reachable via garbage input. Low-Medium severity since it requires either a client bug or deliberate parameter tampering by an already-privileged ops-role user, and reopening a request to `PENDING` isn't itself destructive (no data is lost), but it is inconsistent with how carefully every *other* transition in this same method is guarded.
- **`request_status` schema enum includes `CANCELLED`** ([schema.sql:199](schema.sql:199)) but **no code path in `AddAssetRequestServlet`/`UpdateRequestStatusServlet`/`AssetRequestDAO` ever sets it** — `normalizeStatus()`/`normalizeRequestStatus()` (both servlet and DAO) only recognize `PENDING`/`APPROVED`/`REJECTED`/`FULFILLED`. There is no "employee cancels their own pending request" feature reachable from this module's code — if this exists at all, it must live in a JSP-embedded path not traced this pass; otherwise it's a schema-documented feature with no implementation.
- **`fulfilled_asset_id` never populated**: the schema has a dedicated column linking a `FULFILLED` request to the actual asset that satisfied it ([schema.sql:203](schema.sql:203)), but `updateRequestStatus()`'s `UPDATE` statement only sets `request_status, approved_by, approved_date, remarks` ([AssetRequestDAO.java:129-131](src/main/java/com/mycompany/asset_management_system_ams/AssetRequestDAO.java:129)) — `fulfilled_asset_id` is never written by this module. This mirrors Module 5's `issued_by` finding: the schema models the relationship correctly, but the write path that would populate it doesn't. Practically, this means there's no direct, queryable link from a fulfilled request to the allocation that fulfilled it — reconstructing that link would require inferring it from timing/employee/category coincidence against the `asset_allocation` table, which is unreliable.
- **`priority` and `required_by_date` are schema-modeled but not exposed**: `addAssetRequestAndReturnId()` hardcodes `'NORMAL'` priority unconditionally ([AssetRequestDAO.java:65](src/main/java/com/mycompany/asset_management_system_ams/AssetRequestDAO.java:65)) and never sets `required_by_date`; neither `AddAssetRequestServlet` nor the DAO's parameter list accepts these as inputs — the requester has no way to flag urgency or a needed-by date despite the schema explicitly supporting both (`priority enum('LOW','NORMAL','HIGH','URGENT')`, `required_by_date date`).

---

## 4. Data Model Check

`asset_requests` ([schema.sql:189-215](schema.sql:189)): `request_id, employee_id, department_id, division_id, location_id, category_id, request_type (enum, always NEW_ASSET from this module), request_date, required_by_date, request_status (enum incl. CANCELLED), priority (enum), approved_by, approved_date, fulfilled_asset_id, request_reason, remarks, created_at, updated_at`.

- `request_type` enum includes `REPLACEMENT`/`REPAIR_SUPPORT`/`RETURN_SUPPORT` in addition to `NEW_ASSET` — this module's `addAssetRequestAndReturnId()` hardcodes `'NEW_ASSET'` for every request created through it ([AssetRequestDAO.java:64](src/main/java/com/mycompany/asset_management_system_ams/AssetRequestDAO.java:64)), so the other three request types are schema-modeled but not reachable from this module's own creation path (may be created elsewhere — e.g. Maintenance Requests generating a `REPAIR_SUPPORT` request — not confirmed this pass, flag for Module 11 cross-check).
- `department_id`/`division_id`/`location_id` are auto-populated from the requesting employee's own record via the `INSERT ... SELECT ... FROM employees e` pattern ([AssetRequestDAO.java:61-70](src/main/java/com/mycompany/asset_management_system_ams/AssetRequestDAO.java:61)) rather than being independently settable — sensible, keeps the request's org-scoping consistent with who actually requested it, and closes off a potential inconsistency where a request's recorded department could disagree with the requester's actual department.
- No FK from `asset_requests.approved_by` visible in this excerpt to confirm `ON DELETE` behavior — not verified this pass.

---

## 5. Status Model Check

- 5-value enum (`PENDING`/`APPROVED`/`REJECTED`/`FULFILLED`/`CANCELLED`), of which this module's code only implements 4 transitions, all correctly guarded except the fallback-to-`PENDING` path (§3, Finding 2).
- **No impossible state found** for the transitions that *are* implemented — the guard pattern means a request cannot be `FULFILLED` without having passed through `APPROVED` first, and cannot be `APPROVED`/`REJECTED` a second time once already decided (the guard makes the second attempt a no-op, not an overwrite).

---

## 6. RBAC & Security Check

- **CSRF**: app-wide gap, applies here too — no tokens on either the create or approve/reject/fulfill forms; F3 in particular (privileged approve/reject/fulfill action) has no re-authentication requirement, making it a clean CSRF target for a tricked ASSET_MANAGER/ADMIN session.
- **IDOR**: F1 is genuinely well-protected (server-side employee-identity override, plus a SQL-layer re-check) — a strong, concrete example of the "don't trust the client" principle done correctly. F2's cross-department scope gap (Finding 1) is a real but low-severity access-control looseness, not a full IDOR (it doesn't expose or modify another employee's *existing* data, only lets a Department Head create a new request attributed to an employee outside their department). F4 is unresolved/unverified this pass.
- **RBAC enforcement**: consistent and correctly matches `RoleAccessUtil`'s dedicated `requestApprovalOps` (deliberately narrower than request-creation) and `allEmployeeOps` mappings — no drift found between the servlets' own inline checks and the central map for this module, unlike some other modules audited so far.

---

## 7. Audit Log & Data Integrity Check

- Create and every status transition are individually audit-logged with a distinct action type per outcome (`APPROVED`/`REJECTED`/`FULFILLED`/generic `UPDATED`) — consistent with the app's general pattern, though notably **this module does not log blocked/rejected *attempts*** the way Modules 4-5 do (no `ADD_BLOCKED`-style entry for e.g. an invalid category or inactive employee at creation, or for a transition-guard no-op at approval) — a smaller monitoring footprint than the two immediately preceding modules, though the failure paths do still redirect with a clear `?error=` code visible to the user.
- **`fulfilled_asset_id` gap (§3) is also a data-integrity finding**: the authoritative link from a fulfilled request to its actual fulfilling asset doesn't exist as structured data anywhere, only inferable (unreliably) after the fact.

---

## 8. Missing Features / Gaps

- No employee-initiated **Cancel Request** feature despite schema support (`CANCELLED` status exists, unused).
- `fulfilled_asset_id` never populated — no queryable request→asset fulfillment link.
- `priority`/`required_by_date` not exposed on the create form — every request is effectively unprioritized and undated for urgency purposes.
- No department-scoping for DEPARTMENT_HEAD when creating a request on behalf of an employee (Finding 1).
- No guard against a malformed status value silently resetting a finalized request to `PENDING` (Finding 2).
- `request_type` values beyond `NEW_ASSET` are schema-modeled but not creatable from this module.

---

## 9. Advanced Feature Recommendations

- **P1** — Populate `fulfilled_asset_id` when a request transitions to `FULFILLED` (requires deciding how fulfillment actually links to an allocation — likely needs the Fulfill action to either take an explicit asset selection or be triggered from the Allocation flow itself, cross-reference Module 5).
- **P1** — Close Finding 2: make `normalizeStatus()` reject unrecognized values outright (redirect to `?error=invalidstatus`) instead of silently falling back to `PENDING`, and/or add the same `requiredCurrentStatus` precondition style guard for any transition back to `PENDING`.
- **P2** — Scope DEPARTMENT_HEAD's on-behalf-of request creation to their own department's employees (Finding 1), matching the pattern already established in Module 2's `RoleAssignmentServlet`.
- **P2** — Expose `priority` and `required_by_date` on the create form.
- **P2** — Implement employee-initiated Cancel Request for still-`PENDING` requests.
- **P3** — CSRF tokens (shared app-wide recommendation).
- **P3** — Confirm/implement the other `request_type` values (`REPLACEMENT`/`REPAIR_SUPPORT`/`RETURN_SUPPORT`) if they're meant to be requestable directly rather than only system-generated from other modules.

---

## 10. Test Cases

No dedicated `AssetRequestDAOTest`/`*RequestServletTest` found in the Phase-0 test inventory.

- [ ] **Functional**: EMPLOYEE submits a request; `employee_id` on the created row matches their own linked employee record regardless of what `employeeId` parameter value was submitted
- [ ] ASSET_MANAGER approves a `PENDING` request → status becomes `APPROVED`, `approved_by`/`approved_date` populated
- [ ] Approved request is then marked `FULFILLED` successfully
- [ ] **Regression test for the transition guard (F3's strength — keep this passing)**: two near-simultaneous approve attempts on the same request — exactly one succeeds, the other gets `updatefailed`
- [ ] **Regression test for Finding 2**: submit `requestStatus=garbage` against an already-`FULFILLED` request as ASSET_MANAGER — assert the request status is unchanged (expected to currently **fail**, i.e. it currently *does* get reset to `PENDING`)
- [ ] **Regression test for Finding 1**: DEPARTMENT_HEAD submits `add_request.jsp` with an `employeeId` belonging to a different department — assert rejection (expected to currently **fail**, i.e. it currently succeeds)
- [ ] Attempt to `FULFILLED` a still-`PENDING` request (skipping `APPROVED`) — must fail
- [ ] **RBAC**: DEPARTMENT_HEAD directly POSTing to `UpdateRequestStatusServlet` is denied (confirms the deliberate exclusion documented in F3)
- [ ] AUDITOR (read-only role) cannot POST to either servlet
- [ ] **Security**: direct `curl -X POST /UpdateRequestStatusServlet` with a valid ASSET_MANAGER session and no CSRF-equivalent token succeeds (documents the shared CSRF gap)
- [ ] **IDOR verification for F4**: EMPLOYEE A requests `view_request.jsp?id=<EMPLOYEE_B's_request>` — determine at runtime whether this is blocked (unresolved by static reading this pass)
- [ ] **DB integrity**: attempt inserting an `asset_requests` row for an `INACTIVE` or soft-deleted employee directly against `AssetRequestDAO.addAssetRequestAndReturnId()` — confirm the SQL-layer `JOIN`/`WHERE` guard silently no-ops rather than erroring

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 7 | Core create→approve/reject→fulfill flow works well; no cancel, no fulfillment-asset linkage |
| Lifecycle support | 7 | Transition guards are genuinely strong for 3 of 4 implemented transitions; the fallback-to-PENDING gap is the exception |
| Data integrity | 6 | `fulfilled_asset_id` never populated undermines traceability; otherwise solid |
| UX | 7 | Consistent, role-aware messaging and redirects; no priority/urgency signal exposed |
| Validation | 7 | Good SQL-layer defense-in-depth on creation; the status-transition fallback is the one soft spot |
| RBAC | 8 | Correctly matches the central access-control map; the DEPARTMENT_HEAD department-scoping gap is real but limited-impact |
| Security | 6 | No CSRF (shared gap); strong, genuine IDOR protection on the employee self-service path specifically |
| API integration | 7 | Consistent conventions |
| DB integrity | 6 | Same schema-vs-write-path gap pattern seen in Module 5 |
| Auditability | 6 | Success/transition actions logged; rejection/blocked attempts are not, unlike Modules 4-5 |
| Reliability | 8 | The transition-guard pattern (concurrency-safe, idempotent) is a real strength, consistent with the codebase's best work elsewhere |
| Performance | 7 | No inefficiencies observed |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Covered under Module 24 |

**Overall status: MINOR WORK REQUIRED**

The approve/reject/fulfill workflow's transition-guard design is genuinely strong and consistent with the best engineering seen elsewhere in this codebase (Modules 2, 4, 5). The gaps here are real but modest: one inconsistently-guarded fallback path, one under-scoped cross-department action, and a schema-vs-write-path traceability gap on request fulfillment — none of them Critical, all straightforward to close.
