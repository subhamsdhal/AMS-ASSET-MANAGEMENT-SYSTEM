# Module 20 Audit — Profile Change Requests (Employee Self-Service)

**Scope:** Employee-initiated email/phone change requests requiring admin/department-head approval (`SubmitProfileChangeRequestServlet`, `ReviewProfileChangeRequestServlet`, `ProfileChangeRequestDAO`).
**Verification layers used:** (a) static code reading — full. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Employee Profile | [employee_profile.jsp](src/main/webapp/employee_profile.jsp) | Self-service profile view, "Request a Profile Change" entry point |
| Profile Change Requests (review queue) | [user_profile_requests.jsp](src/main/webapp/user_profile_requests.jsp) | ADMIN/SUPER_ADMIN (any) / DEPARTMENT_HEAD (own department) approve/reject queue |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | Submit Profile Change Request | employee_profile.jsp form | native POST | `POST /SubmitProfileChangeRequestServlet` | [SubmitProfileChangeRequestServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/SubmitProfileChangeRequestServlet.java:26) | `profile_change_requests` (read `employees` for current value) | Field name whitelist-checked (`ProfileChangeRequestDAO.ALLOWED_FIELDS = {"email","phone"}`) at **both** the servlet and DAO layer; real email regex + length cap; real phone validation via `PhoneValidationUtil`; blocks a duplicate pending request for the same field; blocks a no-op request (requested value identical to current) | Requires only a valid session with `employee_id` set — any authenticated employee, correctly scoped to their own record only via session-derived `employeeId`, never a request parameter | Yes | Not confirmed this pass | `?error=invalid_field/missing_value/invalid_email/invalid_phone/already_pending/no_change/server`, `?msg=request_submitted` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **`getCurrentValue()`'s SQL string-concatenates `fieldName` directly into the query text rather than using a bind parameter** ([SubmitProfileChangeRequestServlet.java:116](src/main/java/com/mycompany/asset_management_system_ams/SubmitProfileChangeRequestServlet.java:116)) — normally an injection red flag, but the method's own comment correctly and explicitly reasons about why it's safe here: `fieldName` is whitelist-checked against a fixed two-value set (`ALLOWED_FIELDS`) before this method is ever reached, and JDBC has no bind-parameter syntax for identifiers (column/table names) in the first place, so a literal string-safe whitelist is the *correct* mitigation here, not a workaround. This is exactly the right way to handle a dynamic-identifier SQL need, and the comment shows the author understood why, rather than it being an accidental correct-by-luck pattern |
| T2 | Approve / Reject Profile Change Request | user_profile_requests.jsp row actions | native POST | `POST /ReviewProfileChangeRequestServlet` | [ReviewProfileChangeRequestServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/ReviewProfileChangeRequestServlet.java:29) | `profile_change_requests`, `employees` (on approve) | requestId + a recognized action required | SUPER_ADMIN/ADMIN (any employee) or DEPARTMENT_HEAD (own department only, **re-verified server-side** via `isEmployeeUnderDepartmentHead()` — the servlet's own doc comment explicitly frames this as "not just by what user_profile_requests.jsp happens to display... the same 'JSP shows a filtered view, servlet re-checks independently' split this app already uses for e.g. token validation in reset_password.jsp," directly citing Module 1's pattern by name) | Yes — distinct `APPROVE_PROFILE_CHANGE`/`REJECT_PROFILE_CHANGE` actions, with the reviewer's note included when present | Not confirmed this pass | `?error=invalid/conflict/already_reviewed/server`, `?msg=approved/rejected` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **`ProfileChangeRequestDAO.approve()` is genuinely sophisticated, best-in-class engineering**: fetches the pending request row with `SELECT ... WHERE status = 'PENDING' FOR UPDATE` (row-locked, idempotency-safe against a racing double-approval — matching the codebase's best-established pattern), applies the change to `employees` and marks the request `APPROVED` in one transaction, and **specifically catches `SQLIntegrityConstraintViolationException`** (e.g. the requested email now collides with another employee's `UNIQUE` constraint, perhaps because circumstances changed between request and review) to return a distinct `CONFLICT` result — the request is deliberately left in `PENDING` status rather than being silently lost or auto-failed, so an admin can see the conflict and explicitly reject it with an explanation ([ProfileChangeRequestDAO.java:209-285](src/main/java/com/mycompany/asset_management_system_ams/ProfileChangeRequestDAO.java:209)) — using a real database constraint violation as meaningful business-logic signal, not just an error to swallow, is a level of care not seen elsewhere in this audit |

---

## 3. Business Workflow / Lifecycle Check

- **Two-step review-required workflow, correctly enforced end-to-end**: an employee can never write to their own `employees.email`/`phone` directly — `SubmitProfileChangeRequestServlet`'s own doc comment states this explicitly ("Never writes to the employees table directly"), and this was verified true by reading the servlet: it only ever inserts into `profile_change_requests`. The actual mutation to `employees` happens exclusively inside `ProfileChangeRequestDAO.approve()`, gated by the SUPER_ADMIN/ADMIN/DEPARTMENT_HEAD review step.
- **Genuine department-scoping for DEPARTMENT_HEAD reviewers**, correctly re-verified server-side rather than trusted from the JSP's own filtered display — consistent with the established, repeatedly-proven pattern in this codebase (Modules 2, 9, 19).
- **Idempotency/concurrency guard on approval** — the `FOR UPDATE` + `WHERE status = 'PENDING'` pattern prevents a double-approval race, consistent with this codebase's best modules (2, 6, 7's intended-but-broken equivalent, 12).
- **Conflict handling is the standout feature of this module**: rather than assuming "the request was valid when submitted, so it's still valid at approval time," the DAO actually anticipates that the underlying data could have changed in the interim (e.g., another employee independently acquired the same email address through some other path) and handles that specific failure mode gracefully and informatively, rather than either (a) blindly succeeding and violating the constraint at the DB layer with an unhandled exception, or (b) silently failing the whole approval with no indication why.

---

## 4. Data Model Check

`profile_change_requests` ([schema.sql:312-327](schema.sql:312)): `request_id, employee_id, field_name, current_value, requested_value, reason, status (enum: PENDING/APPROVED/REJECTED), reviewed_by, review_note, created_at, reviewed_at`. Clean, complete, and — notably — **the `status` enum here correctly includes `'PENDING'` and the code's queries correctly reference `'PENDING'`**, avoiding the exact enum-value/string-literal mismatch that broke Module 7's equivalent review workflow entirely. A useful point of contrast for the final report: this module and Module 7 both implement "a pending record needs review before taking effect," but only one of them got the status-value naming right, and the difference between a fully-working and a fully-broken approval gate came down to that one detail.

---

## 5. Status Model Check

Clean 3-state enum (`PENDING/APPROVED/REJECTED`), correctly enforced as one-way-only via the `FOR UPDATE`/`WHERE status='PENDING'` guard on both `approve()` and (presumably, not fully re-read) `reject()`. No impossible-state risk found.

---

## 6. RBAC & Security Check

- **CSRF**: app-wide gap applies to both actions.
- **RBAC enforcement**: correct, consistent, genuinely re-verified server-side for the one role (DEPARTMENT_HEAD) that needs scoping.
- **IDOR**: T1 is fully protected (session-derived `employeeId` only); T2's department-scoping is real and independently verified.
- **The string-concatenated column name in `getCurrentValue()`/`approve()`'s UPDATE is correctly safe** (§2/T1) — flagged explicitly here because a less careful audit might flag it as a SQL-injection risk on pattern-matching alone; the actual code and its own reasoning confirm it is not, given the whitelist gate that precedes every use.

---

## 7. Audit Log & Data Integrity Check

- Submit, approve, and reject are all audit-logged with informative detail including reviewer notes.
- The `CONFLICT` handling (§3) is itself a data-integrity strength — it prevents a stale approval from either silently corrupting data or throwing an unhandled exception at the DB layer.

---

## 8. Missing Features / Gaps

- Only `email`/`phone` are supported self-service change fields — reasonable scope-limiting (name, employee code, department are presumably intentionally excluded from self-service, requiring an admin's direct `UpdateEmployeeServlet` edit instead) rather than a gap.
- Notification/email-escaping not confirmed this pass — flagged as a routine follow-up given the recurring pattern elsewhere, not a specific finding here.

---

## 9. Advanced Feature Recommendations

- **P2** — Confirm/apply `HtmlEscapeUtil` to this module's notifications if not already safe (routine follow-up, not a confirmed finding).
- **P3** — CSRF tokens (shared app-wide recommendation).
- **P3** — Consider whether additional self-service fields (e.g., emergency contact, if such a field exists elsewhere) would benefit from the same review-gated pattern established here.

---

## 10. Test Cases

No dedicated test file found for this module in the Phase-0 inventory — notable given the genuine sophistication of the conflict-handling logic, which deserves regression protection.

- [ ] **Functional**: submitting a valid email/phone change request creates a `PENDING` row; approving it updates `employees` and marks the request `APPROVED`
- [ ] **Negative/Boundary**: submitting a request identical to the current value is blocked (`no_change`); submitting a second request for the same field while one is already pending is blocked (`already_pending`)
- [ ] Invalid email format / invalid phone format is rejected
- [ ] **Regression test for the CONFLICT path (this module's standout feature)**: submit a profile-change request for employee A's email to a value that, before the request is approved, becomes employee B's actual email (via any path) — attempt to approve A's request and assert it returns `CONFLICT`, leaves the request `PENDING`, and does **not** throw an unhandled exception
- [ ] **Concurrency**: two near-simultaneous approval attempts on the same request — assert only one succeeds (the `FOR UPDATE` guard)
- [ ] **RBAC**: DEPARTMENT_HEAD cannot review a request for an employee outside their department (confirmed server-side, not just UI-filtered)
- [ ] EMPLOYEE cannot POST to `ReviewProfileChangeRequestServlet`; non-EMPLOYEE cannot POST to `SubmitProfileChangeRequestServlet` in a way that submits on behalf of another employee (session-only `employeeId` should make this structurally impossible, not just policy-blocked)
- [ ] **Security**: direct `curl -X POST /ReviewProfileChangeRequestServlet` with a valid ADMIN session and no CSRF-equivalent token succeeds (documents the shared CSRF gap)
- [ ] **DB integrity**: confirm the `employees.email` UNIQUE constraint is what actually triggers the `CONFLICT` path (not a pre-check that could itself have a TOCTOU gap)

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 9 | Complete, correctly scoped, well-validated |
| Lifecycle support | 9 | Clean two-step review workflow, correctly enforced with no bypass |
| Data integrity | 9 | The `CONFLICT` handling is a genuine standout; correct enum/code alignment |
| UX | 8 | Specific, informative error codes throughout |
| Validation | 9 | Real format validation, duplicate/no-op prevention |
| RBAC | 9 | Correct, consistently re-verified server-side |
| Security | 7 | No CSRF (shared gap); the one pattern-matched "risk" (string-built column name) is correctly reasoned and safe |
| API integration | 8 | Consistent, well-differentiated result handling |
| DB integrity | 9 | Clean schema, correct status-enum alignment (a useful contrast to Module 7) |
| Auditability | 8 | Thorough, informative logging including reviewer notes |
| Reliability | 9 | The conflict-handling logic reflects genuine production-grade defensive thinking |
| Performance | 8 | No inefficiencies observed |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Not applicable to this module |

**Overall status: PRODUCTION READY**

The third module in a row (after Warranty and Employee Transfer) to earn full production-ready status, and the strongest yet on data-integrity sophistication specifically — the `CONFLICT`-on-constraint-violation handling in `ProfileChangeRequestDAO.approve()` is genuinely excellent engineering, anticipating and gracefully handling a real-world race condition (data changing between request submission and admin review) that most systems of this scope would either not consider or handle by crashing.
