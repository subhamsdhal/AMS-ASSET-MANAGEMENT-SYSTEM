# Module 15 Audit — Departments

**Scope:** Department master-data CRUD (`AddDepartmentServlet`, `UpdateDepartmentServlet`, `DeleteDepartmentServlet`, `DepartmentDAO`). Resolves an open question carried over from Module 9.
**Verification layers used:** (a) static code reading — full. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Department List | [departments.jsp](src/main/webapp/departments.jsp) | List, entry point |
| Add Department | [add_department.jsp](src/main/webapp/add_department.jsp) | Create |
| Edit Department | [edit_department.jsp](src/main/webapp/edit_department.jsp) | Update |
| View Department | [view_department.jsp](src/main/webapp/view_department.jsp) | Read-only detail |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| O1 | Add Department | [add_department.jsp](src/main/webapp/add_department.jsp) form | native POST | `POST /AddDepartmentServlet` | [AddDepartmentServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/AddDepartmentServlet.java:15) | `departments`, `audit_logs` | code + name required, duplicate code/name checked | Uses `RoleAccessUtil.hasAccess(role, "DEPARTMENT_MANAGEMENT", "CREATE")` — the module/action-based overload (not the URI-based one used elsewhere) — SUPER_ADMIN/ADMIN per that method's hardcoded logic ([RoleAccessUtil.java:571-577](src/main/java/com/mycompany/asset_management_system_ams/RoleAccessUtil.java:571)) | Yes — `CREATE` | Yes, **correctly HTML-escaped** ([AddDepartmentServlet.java:83-84](src/main/java/com/mycompany/asset_management_system_ams/AddDepartmentServlet.java:83)) | `?error=invalid/duplicatecode/duplicatename/server` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Another confirmed instance of the `HtmlEscapeUtil` fix being correctly applied (4th confirmed module: Disposal, Employees, and now Departments — reinforcing that the fix exists and was applied to *some* modules but not swept everywhere, e.g. Maintenance/Returns) |
| O2 | Edit Department | edit_department.jsp | native POST | `POST /UpdateDepartmentServlet` | not fully re-traced this pass | `departments`, `audit_logs` | — | `DEPARTMENT_MANAGEMENT`/`EDIT` action, same SUPER_ADMIN/ADMIN gate | — | — | — | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **`DepartmentDAO.updateDepartment()` does not update `employees.department_name`** ([DepartmentDAO.java:112-132](src/main/java/com/mycompany/asset_management_system_ams/DepartmentDAO.java:112) — the `UPDATE` statement only touches the `departments` row itself) — see Finding 1, which resolves an open question from Module 9 |
| O3 | Delete Department | departments.jsp row action | native **POST** | `POST /DeleteDepartmentServlet` | [DeleteDepartmentServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/DeleteDepartmentServlet.java:20) | `departments` (hard `DELETE`), `audit_logs` | Multi-table dependency check before allowing the delete (§3) | `DEPARTMENT_MANAGEMENT`/`DELETE`, SUPER_ADMIN/ADMIN | Yes, escaped | Yes, escaped | `?error=invalid/deleteblocked&reason=.../server` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **This is a real, hard `DELETE FROM departments WHERE department_id = ?`** ([DepartmentDAO.java:134-139](src/main/java/com/mycompany/asset_management_system_ams/DepartmentDAO.java:134)) — genuinely permanent, unlike the soft-delete pattern used for Assets (never deletable) and Employees (Module 9). The servlet's own code comment is explicit about this being intentional given the mitigations in place (see Finding 2 below), not an oversight, and also documents the same GET→POST CSRF-adjacent fix already found on Employees/Categories/Maintenance-resolution in this audit series |

### Finding 1 (Low, resolves an open item from Module 9) — `employees.department_name` denormalized column is write-orphaned but appears to be a dead/unused column, not an active staleness bug

Module 9 flagged `employees.department_name` (a denormalized cache of the employee's department name, alongside the normalized `department_id` FK) as a risk if any department-rename path forgot to keep it in sync. This module's `updateDepartment()` confirms that risk is real **on the write side** — renaming a department never touches `employees.department_name` for any employee in it. However, a targeted search of the entire codebase for direct reads of this specific column (`e.department_name`/`employees.department_name`, as distinct from the normalized `departments.department_name`/`d.department_name` used everywhere else) found **zero matches** — every department-name display observed in this audit series so far is sourced via a live `JOIN` to `departments`, not from this cached column. **Conclusion: this column is very likely dead/vestigial rather than an active data-staleness bug** — downgrading Module 9's flagged risk from "potential live bug" to "orphaned schema cruft," though this should still be confirmed (not just inferred from a grep) before being fully dismissed, since a report or export JSP not read in this pass could still reference it directly.

### Finding 2 (informational — good practice, not a defect) — Department deletion's dependency-check is a documented, thorough fix

`DepartmentDAO.getDepartmentDeleteBlockReason()`'s own code comment explains a **real, previously-existing bug** in detail: the original check only verified `asset_count`/`employee_count` before allowing a hard delete, but `departments.department_id` is actually referenced by **five** tables, not two. Two of the missed references (`asset_requests`, `railway_locations`) are `ON DELETE SET NULL`, meaning a department with old requests or mapped locations but zero *current* assets/employees would previously have been deleted successfully while **silently orphaning those historical records' department reference with no warning** — a real, if quiet, data-integrity loss. A third missed reference (`employee_role_assignments.department_id`, `ON DELETE NO ACTION`, functionally `RESTRICT`) would previously have caused the raw `DELETE` to throw an FK-constraint `SQLException`, generically caught and surfaced to the admin as an opaque "Server error. Please try again." with no indication of the actual cause. The fix — explicitly described as verified against `information_schema` rather than assumed — now checks all five real dependencies before allowing the delete, and specifically recommends *disabling* rather than deleting a department with historical request records, correctly recognizing that some dependent data (history) should block deletion outright rather than just being nulled out. **This is genuinely excellent defensive engineering, on par with `EmployeeDAO.getEmployeeDeleteBlockReason()` which it explicitly credits as the model it followed.**

---

## 3. Business Workflow / Lifecycle Check

- **Department deletion remains a permanent, hard DELETE** (unlike Assets/Employees) — this is a deliberate design choice given the thorough dependency-blocking now in place (Finding 2), and the servlet's guidance to disable-not-delete when historical data exists is the correct mitigation, but it does mean a department with *zero* dependents can still be genuinely, unrecoverably removed — worth confirming this is the intended behavior for what is otherwise fairly foundational reference data.
- **`department_head_user_id`** is set at creation/edit and separately kept in sync by Module 2's `RoleAssignmentDAO.syncDepartmentHeadColumn()` (per that module's own documented rationale) when a Department Head duty is dynamically assigned/reassigned — worth noting this column has **two possible writers** (this module's direct edit form, and Module 2's dynamic-duty-assignment side-effect), which is a reasonable design (an ADMIN can directly appoint a head via this module, or the head can emerge from a Role & Duty Assignment action) but is worth confirming the two never fight each other (e.g., does editing the department via this module's Edit form ever silently overwrite a head that was set via the dynamic-duty mechanism, or vice versa, without either side being aware of the other's write?) — not resolved with full certainty this pass, flagged for a targeted follow-up.

---

## 4. Data Model Check

`departments` ([schema.sql:396-409](schema.sql:396)): `department_id, department_name (UNIQUE), description, department_head_user_id, status (enum), created_at, updated_at, department_code (UNIQUE)`. Clean, appropriately constrained (both name and code are uniquely enforced at the DB layer).

- Finding 1 (above) is the only data-model concern of note, and it's now assessed as low-risk.

---

## 5. Status Model Check

`status`: simple `ACTIVE`/`INACTIVE` — no complex transitions, no impossible-state risk identified.

---

## 6. RBAC & Security Check

- **CSRF**: app-wide gap; Delete in particular is a genuine, irreversible action (like Module 13's disposal) with no CSRF protection — worth the same elevated-priority flag given the permanence of the action.
- **RBAC enforcement**: this module uses the **module/action-based** `RoleAccessUtil.hasAccess(role, module, action)` overload rather than the URI-based one used almost everywhere else in the codebase — worth noting as a second, differently-shaped access-control code path existing in parallel (per Module 2's own findings about this overload: "SUPER_ADMIN is currently NOT a standing implicit rule app-wide in RoleAccessUtil... must be explicitly mapped for every module/action" — confirmed here, `DEPARTMENT_MANAGEMENT` explicitly lists SUPER_ADMIN in its CREATE/EDIT/DELETE checks, so no gap found, but this dual-code-path design is worth flagging as a maintainability risk: a future change to the URI-based map wouldn't automatically apply here, and vice versa).
- **GET→POST fix confirmed again**: Delete's own comment cites this as the same class of previously-fixed vulnerability found on Employees/Categories/Maintenance — good corroborating evidence of a real, if not fully swept, security-hardening pass having occurred across multiple modules.

---

## 7. Audit Log & Data Integrity Check

- All three actions are audit-logged with escaped, informative messages.
- Finding 2 is itself the standout data-integrity strength of this module.

---

## 8. Missing Features / Gaps

- Confirm whether `employees.department_name` is truly dead (Finding 1) or has a reader this pass missed (e.g., in an unaudited export/report JSP).
- Confirm the two-writer relationship on `department_head_user_id` (this module vs. Module 2's dynamic sync) doesn't have an unhandled conflict case.
- Department deletion, while well-guarded, is still permanent for a department with no dependents — worth a product decision on whether foundational reference data like this should ever be truly deletable versus deactivate-only.

---

## 9. Advanced Feature Recommendations

- **P2** — Confirm and either remove `employees.department_name` (if genuinely dead) or wire it up correctly (if some unaudited path does read it).
- **P2** — Confirm/document the interaction between this module's direct head-appointment and Module 2's dynamic-duty-driven head sync.
- **P3** — Consider disallowing hard department deletion entirely in favor of deactivate-only, given how foundational this reference data is to the rest of the schema (five other tables reference it).
- **P3** — CSRF token specifically for Delete, given its irreversibility (same reasoning as Module 13).

---

## 10. Test Cases

[DepartmentModuleSecurityTest.java](src/test/java/com/mycompany/asset_management_system_ams/DepartmentModuleSecurityTest.java) exists per the Phase-0 inventory — not yet read in full this pass, flag to confirm its coverage in a follow-up.

- [ ] **Functional**: creating a department with a unique code/name succeeds; duplicate code or name is rejected
- [ ] **Regression test for Finding 2 (the module's key strength — protect it)**: attempt to delete a department that has only *historical* `asset_requests`/`railway_locations` references (zero current assets/employees) — assert it is blocked with a clear reason, not silently deleted with orphaned references (this should currently **pass** — confirm as a regression guard, not a new finding)
- [ ] Attempt to delete a department referenced by `employee_role_assignments` — assert a clean, specific error message, not a raw server-error page (should currently **pass**)
- [ ] **Regression test for Finding 1**: rename a department, then check whether any employee row's cached `department_name` (if the column is genuinely read somewhere) goes stale — resolves the open question definitively
- [ ] **RBAC**: DEPARTMENT_HEAD/ASSET_MANAGER/AUDITOR cannot create/edit/delete a department (view-only per `deptViewOps`, confirmed wider than manage access)
- [ ] **Security**: direct `curl -X POST /DeleteDepartmentServlet` with a valid ADMIN session and no CSRF-equivalent token permanently deletes a real department (documents the elevated-severity CSRF exposure given irreversibility)
- [ ] **DB integrity**: confirm `uk_departments_department_name`/`department_code` UNIQUE constraints hold even bypassing the application-level duplicate pre-checks

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 8 | Complete CRUD, well-validated |
| Lifecycle support | 7 | Deliberate hard-delete-with-strong-guards design; a deactivate-only model would be even safer for foundational reference data |
| Data integrity | 8 | Finding 2 is a genuine standout; Finding 1 is a minor, now-downgraded concern |
| UX | 7 | Clear error codes including a specific delete-blocked reason surfaced to the user |
| Validation | 8 | Thorough duplicate-checking |
| RBAC | 7 | Correct, but uses a second, parallel access-control code path worth consolidating |
| Security | 6 | No CSRF (shared gap, elevated concern for the irreversible Delete action); GET→POST fix confirmed applied |
| API integration | 7 | Consistent conventions |
| DB integrity | 9 | The five-table dependency check is genuinely best-in-class engineering |
| Auditability | 8 | Complete, escaped, informative logging on all three actions |
| Reliability | 8 | Well-guarded against the exact class of silent-data-loss bug this audit's methodology looks for |
| Performance | 7 | No inefficiencies observed |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Covered under Module 24 |

**Overall status: MINOR WORK REQUIRED**

Finding 2 (the five-table dependency check) is one of the best-documented, most thorough pieces of defensive engineering found anywhere in this audit — a genuine model for how "don't silently orphan or opaquely fail on delete" should be done, and explicitly done in direct imitation of an equally good fix in the Employees module. The only real open item is confirming Finding 1's now-likely-dead column, which is low-stakes regardless of the answer.
