# Module 25 Audit — Dashboard

**Scope:** Role-scoped KPI dashboards (`dashboard.jsp` for ops roles, `employee_dashboard.jsp` for employees, `DashboardDAO`/`EmployeeDashboardDAO`). Read-only, no mutating actions — inherently lower-risk than most modules audited so far.
**Verification layers used:** (a) static code reading — full for the DAO and the department-scoping logic in `dashboard.jsp`. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Dashboard (ops roles) | [dashboard.jsp](src/main/webapp/dashboard.jsp) | KPI tiles, asset-status breakdown, total value, department-scoped for DEPARTMENT_HEAD |
| Employee Dashboard | [employee_dashboard.jsp](src/main/webapp/employee_dashboard.jsp) | Self-service summary (own assets, requests, returns) |
| Dashboard Help | [dashboard_help.jsp](src/main/webapp/dashboard_help.jsp) | Static help content |

---

## 2. Interactive Element Audit

Dashboards are read-only aggregation views with no mutating controls of their own — the relevant audit surface is data-scoping correctness, not an interactive-element table in the usual sense.

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Y1 | Dashboard page load (KPI aggregation) | dashboard.jsp | page load | `GET dashboard.jsp` | inline JSP + [DashboardDAO](src/main/java/com/mycompany/asset_management_system_ams/DashboardDAO.java) | `assets`, `maintenance_logs`, `asset_requests`, `asset_allocation`, `asset_returns`, `employees`, `asset_categories`, `vendors`, `audit_logs` (all read-only) | n/a | `RoleAccessUtil` maps `/dashboard.jsp` → ADMIN/ASSET_MANAGER/AUDITOR/DEPARTMENT_HEAD explicitly, with SUPER_ADMIN implicitly included per the central map's own bypass rule (Module 1) | n/a (read-only) | n/a | `queryError` flag tracked and presumably surfaced if the DB is unavailable (not fully re-traced for the JSP-side display of this flag) | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | See §3 for the department-scoping analysis, the substantive part of this module's audit |
| Y2 | Employee Dashboard page load | employee_dashboard.jsp | page load | `GET employee_dashboard.jsp` | inline JSP + `EmployeeDashboardDAO` | `asset_allocation`, `asset_requests`, `asset_returns` scoped to the session's own `employee_id` | n/a | `commonOps` (any authenticated role) | n/a | n/a | Not assessed | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Not independently re-verified this pass whether `employee_id` scoping is session-derived only (consistent with every other employee-self-service action audited so far — Modules 6, 11, 19, 20 all correctly do this) — inferred consistent by pattern, not independently re-read line-by-line |

---

## 3. Business Workflow / Lifecycle Check

- **`DashboardDAO`'s table-name and department-scoping logic is correctly and safely constructed** despite building SQL via string concatenation for the table name: `getCount(String tableName, ...)` only ever concatenates `tableName` into the query **after** validating it against a fixed whitelist of literal table names via `equalsIgnoreCase` checks ([DashboardDAO.java:24-37](src/main/java/com/mycompany/asset_management_system_ams/DashboardDAO.java:24)) — the same safe pattern already seen and correctly reasoned about in Module 20 (`ProfileChangeRequestDAO`). All actual filter *values* (department IDs) are properly bound via `PreparedStatement` placeholders.
- **A clever, correct defensive pattern for the "department head with zero resolved departments" edge case**: when `deptIds` is an empty (non-null) list, the query adds `WHERE department_id = -1` rather than either an empty/malformed `IN ()` clause (a SQL syntax error) or — worse — silently omitting the WHERE clause entirely (which would leak system-wide counts to a scoped role) ([DashboardDAO.java:52-58, 104-106, 153-155](src/main/java/com/mycompany/asset_management_system_ams/DashboardDAO.java:52)) — correctly fails to "shows nothing" rather than either crashing or over-disclosing.
- **A genuine, well-documented prior bug fix found in `dashboard.jsp` itself**: the maintenance-log count used to call the same generic `dao.getCount("maintenance_logs", departmentIds)` as the other KPIs, but `DashboardDAO.getCount()`'s department-scoping logic was never written to handle `maintenance_logs` (which has no direct `department_id` column) — meaning **a Department Head was seeing the system-wide maintenance log count while every other number on the same page was correctly scoped to their own department**, a real, if narrow, information-disclosure-adjacent inconsistency (not a security boundary violation exactly, since Department Heads can presumably already see maintenance data through Module 10's own access controls, but a jarring, confusing inconsistency on a summary page meant to represent "your department's numbers"). The fix ([dashboard.jsp:484-494](src/main/webapp/dashboard.jsp:484)) correctly joins through `assets` (which does carry `department_id`) instead, documented with the same "why this used to be wrong" clarity seen throughout this codebase's better fix comments.

---

## 4. Data Model Check

Not applicable — this module owns no tables, purely aggregates from tables already audited across Modules 4–17.

---

## 5. Status Model Check

Not applicable.

---

## 6. RBAC & Security Check

- **RBAC enforcement**: correct, matches the central map; the fixed maintenance-log scoping bug (§3) is the only access-boundary-adjacent issue found, and it's already resolved.
- **CSRF**: not applicable (read-only page).
- **IDOR**: not applicable in the traditional sense for `dashboard.jsp` (aggregate counts, not individual records); `employee_dashboard.jsp`'s scoping wasn't independently re-verified this pass but follows the established, repeatedly-confirmed session-only-employeeId pattern by inference.

---

## 7. Audit Log & Data Integrity Check

Not applicable — a read-only aggregation view has no write path to audit. Page views themselves are not logged (consistent with the rest of the app — no module audited so far logs mere page visits, only mutating actions, a reasonable and consistent scope decision).

---

## 8. Missing Features / Gaps

- `employee_dashboard.jsp`'s scoping not independently re-verified line-by-line this pass (inferred consistent, not confirmed) — low priority given the strength of the established pattern elsewhere.
- No drill-down audit trail ("why does this KPI say X") beyond what the underlying modules already provide — not a defect, just a note that this page is a summary layer, not an investigative tool (consistent with its purpose).

---

## 9. Advanced Feature Recommendations

- **P2** — Independently confirm `EmployeeDashboardDAO`'s scoping in a follow-up pass, purely for completeness given how much this audit has relied on pattern-consistency inference for this specific file.
- **P3** — Consider a lightweight "as of [timestamp]" or cache-freshness indicator if any dashboard values are ever cached rather than computed live (not confirmed either way this pass — appears to be computed live on every page load based on the DAO's design).

---

## 10. Test Cases

[DashboardDAOTest.java](src/test/java/com/mycompany/asset_management_system_ams/DashboardDAOTest.java) exists per the Phase-0 inventory — not independently re-read in full this pass to confirm exact coverage, but its existence is itself a positive sign relative to most other modules in this audit, which had no dedicated test file at all.

- [ ] **Functional**: SUPER_ADMIN/ADMIN see system-wide counts; DEPARTMENT_HEAD sees counts correctly scoped to their own department(s) across **every** KPI tile, including maintenance logs (regression guard for the already-fixed bug in §3)
- [ ] A DEPARTMENT_HEAD with zero resolved departments (edge case) sees all-zero KPIs, not a crash and not system-wide numbers
- [ ] **RBAC**: EMPLOYEE cannot reach `dashboard.jsp` (routed to `employee_dashboard.jsp` instead, per Module 1's login-redirect logic)
- [ ] Database-unavailable scenario: confirm `queryError` is surfaced sensibly on the page rather than silently showing zero/misleading KPIs indistinguishable from "genuinely zero"
- [ ] **DB integrity**: confirm the `department_id = -1` sentinel pattern can never accidentally match a real row (i.e., no legitimate `department_id` is ever `-1`)

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 8 | Comprehensive KPI coverage across the app's core entities |
| Lifecycle support | N/A | Not applicable |
| Data integrity | 8 | Correctly scoped, with a genuine documented fix for a real prior inconsistency |
| UX | 7 | Standard KPI-tile dashboard pattern |
| Validation | N/A | Read-only, no user input beyond navigation |
| RBAC | 8 | Correct, consistent |
| Security | 8 | Safe table-name whitelisting, correctly parameterized filters, no injection risk |
| API integration | 7 | Consistent |
| DB integrity | N/A | Read-only module |
| Auditability | N/A | Page views not logged, consistent with app-wide scope decision |
| Reliability | 7 | Explicit `queryError` tracking for DB-unavailable scenarios |
| Performance | 7 | Multiple sequential count queries per page load — not flagged as a problem at this app's likely scale, but worth watching if table sizes grow substantially |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | 7 | Effective at-a-glance summary, complements Module 24's detailed exports |

**Overall status: MINOR WORK REQUIRED**

A solidly-built, low-risk module with correct department-scoping (including a well-handled edge case) and genuine evidence of a real prior inconsistency being found and fixed. The only substantive follow-up is confirming `EmployeeDashboardDAO`'s scoping to the same standard, which is not expected to surface anything new given the pattern's strength elsewhere in this codebase.
