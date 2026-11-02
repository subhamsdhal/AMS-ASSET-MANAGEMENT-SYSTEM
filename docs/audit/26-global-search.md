# Module 26 Audit — Global Search

**Scope:** Cross-entity search (`global_search.jsp`, ~996 lines, no dedicated servlet — the search logic, query construction, and rendering all live in one large JSP).
**Verification layers used:** (a) static code reading — full for the role-gating structure and two representative entity-search blocks (Assets, Employees); the remaining entity blocks (Categories, Vendors, Allocation, Returns, Maintenance, Requests, Physical Verification, Disposal, Audit Logs — per the file's own section structure) were swept for the same `canViewAdminData`/`canViewAudit` gating pattern rather than each fully re-read. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Global Search | [global_search.jsp](src/main/webapp/global_search.jsp) | Single search box querying across Assets, Employees, Categories, Vendors, Allocations, Returns, Maintenance, Requests, Physical Verification, Disposal, and Audit Logs |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Z1 | Global Search query | global_search.jsp search box | native GET | `GET global_search.jsp?q=...` | inline JSP | Assets, Employees, Categories, Vendors, Allocation, Returns, Maintenance, Requests, Physical Verification, Disposal, Audit Logs (all read) | Search term correctly bound via `PreparedStatement`/`?` placeholders throughout (`addAll(allResults, con, sql, q, debugMessages)`) — no SQL injection risk found | **`RoleAccessUtil` maps `/global_search.jsp` → `commonOps`, i.e. *any* authenticated role including EMPLOYEE** ([RoleAccessUtil.java:441](src/main/java/com/mycompany/asset_management_system_ams/RoleAccessUtil.java:441)) — appropriate for a page whose *existence* should be broadly reachable, but **see Finding 1: the page-level access grant is not matched by equivalent per-category result gating** | Not confirmed | n/a | Not assessed | Code | **PARTIALLY WORKING — see Finding 1** | **High** | See Finding 1 |

### Finding 1 (High) — Global Search discloses Asset and Employee data to roles explicitly excluded from viewing that same data through its own dedicated module

The page correctly gates **two** of its search categories behind role checks: Disposal results require `canViewAdminData` (`isSuperAdmin || isAssetManager || isAuditor`, [global_search.jsp:744](src/main/webapp/global_search.jsp:744)) and Audit Log results require `canViewAudit` (`isSuperAdmin || isAuditor`, [global_search.jsp:778](src/main/webapp/global_search.jsp:778)) — both consistent with those modules' own dedicated-page access lists (Module 13, Module 3).

**However, the Assets search block (`if (hasAssets)`, [global_search.jsp:239](src/main/webapp/global_search.jsp:239)) and the Employees search block (`if (hasEmployees)`, [global_search.jsp:329](src/main/webapp/global_search.jsp:329)) carry no equivalent role guard at all** — they run and return results for any authenticated user, including EMPLOYEE. This directly contradicts the access-control decisions this audit has already confirmed elsewhere in the same codebase:

- **Employees**: Module 9 (via `RoleAccessUtil`'s `employeeViewOps`) restricts `employees.jsp`/`view_employee.jsp` to SUPER_ADMIN/ADMIN/DEPARTMENT_HEAD/AUDITOR — **EMPLOYEE and ASSET_MANAGER are deliberately excluded** from the employee directory. Global Search's employee-search block has no such restriction: an EMPLOYEE searching any term matching an employee code, name, designation, or department returns a result card showing that employee's code, full name, designation, department, and status ([global_search.jsp:369-382](src/main/webapp/global_search.jsp:369) — `title_text`/`detail_text` construction), directly linking to `view_employee.jsp?id=N` (which *would* then correctly 403 if clicked, since that page's own access list is unaffected — but the summary data is already disclosed in the search results themselves, before any click). **Any employee can browse the entire employee directory's core details through the search box, a capability the dedicated Employees module explicitly withholds from that same role.**
- **Assets**: Module 4 (via `RoleAccessUtil`'s `assetViewOps`) restricts `assets.jsp`/`view_asset.jsp` to SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR/DEPARTMENT_HEAD — **EMPLOYEE is excluded** from the general asset register (employees only see their *own* allocated assets via `employee_assets.jsp`, a deliberately narrower, self-scoped view per Module 5). Global Search's asset-search block is similarly unguarded, letting an EMPLOYEE search and see any asset in the organization's register — code, name, category, vendor, status, location — not just their own allocated ones.

The two categories that *are* gated (Disposal, Audit Logs) prove the page's author was aware of and applied this exact kind of restriction elsewhere on the very same page — making the Assets/Employees omission look like an inconsistency in an otherwise-deliberate design, not a case where role-scoping was never considered for this feature at all. Whether the remaining ungated categories (Categories, Vendors, Allocation, Returns, Maintenance, Requests, Physical Verification — not individually re-confirmed this pass) follow the same unguarded pattern is a direct, high-value follow-up: given Assets and Employees (the two checked in depth) are both unguarded while Disposal and Audit Logs are both correctly guarded, the remaining seven are more likely to lean toward "unguarded" by the same inconsistency, but this should be confirmed file-section-by-file-section rather than assumed.

---

## 3. Business Workflow / Lifecycle Check

Not a lifecycle-bearing module — a pure read/query feature layered across the entities every other module already manages.

---

## 4. Data Model Check

Not applicable — no dedicated tables.

---

## 5. Status Model Check

Not applicable.

---

## 6. RBAC & Security Check

- **Finding 1 is this module's central and most serious issue** — a real, concrete access-control bypass, not a hypothetical one: the mechanism (page-level `commonOps` access + category-level gating that's inconsistently applied) is exactly the kind of subtle cross-cutting gap a module-by-module audit is designed to catch, since neither Module 4's nor Module 9's own audit would have surfaced it (both correctly describe their *own* dedicated pages' access control; the leak happens through a *third* page that re-implements its own, less complete, copy of that access logic).
- **This is functionally an IDOR/broken-access-control finding at the feature level**: the underlying data isn't reached by manipulating an ID parameter (the classic IDOR shape), but by using an alternate, insufficiently-scoped code path (Global Search) to reach data a more heavily-scoped primary path (Assets/Employees modules) correctly protects — the practical effect on confidentiality is the same.
- **No SQL injection risk found** — parameterization is consistent and correct throughout.
- **The extensive `tableExists`/`columnExists` schema-adaptive pattern** (same style as Modules 7, 10, 21) is applied consistently here too, and does not itself introduce any new risk — it governs *which columns are searchable*, not *who is allowed to search them*, so it's orthogonal to Finding 1.

---

## 7. Audit Log & Data Integrity Check

- No audit logging found for search queries (reasonable — a read-only search feature logging every keystroke/query would likely be excessive), though worth noting that **if** Finding 1 is fixed by narrowing what's searchable per role, no audit-trail change is needed for that fix specifically.

---

## 8. Missing Features / Gaps

- **Finding 1**: Assets and Employees search results are not role-scoped to match their dedicated modules' access lists; Categories/Vendors/Allocation/Returns/Maintenance/Requests/Physical Verification are unconfirmed and should be checked with the same scrutiny.
- No pagination beyond each category's own `LIMIT 30` — reasonable for a quick-search feature, not flagged as a defect.

---

## 9. Advanced Feature Recommendations

- **P0** — Apply the same `canViewAdminData`/`canViewAudit`-style role gating already used for Disposal and Audit Logs to the Assets and Employees search blocks (and confirm/fix the remaining seven categories), matching each category's gate to its own dedicated module's `RoleAccessUtil` entry exactly — this is the single most valuable, concrete, mechanical fix identified in this half of the audit, given it's a real confirmed data-exposure gap with a clear, precedented fix pattern already present on the same page.
- **P1** — Audit the remaining seven search categories individually against their dedicated modules' access lists (Categories vs. Module 16, Vendors vs. Module 17, Allocation vs. Module 5, Returns vs. Module 12, Maintenance vs. Module 10, Requests vs. Module 6, Physical Verification vs. Module 7) to fully close out this finding rather than leaving it partially confirmed.
- **P2** — For Employees specifically, consider whether EMPLOYEE should see *any* colleague search results (e.g., a minimal "name + department" directory-style result) as an intentional, narrower feature, versus the current de facto full disclosure — a genuine product decision, not purely a bug fix, once the immediate over-exposure is closed.

---

## 10. Test Cases

No dedicated test file found for this module in the Phase-0 inventory — directly relevant given Finding 1's nature (an access-control gap a unit/integration test would have caught immediately if the test suite had ever compared this page's exposed data against its sibling modules' RBAC lists).

- [ ] **Regression test for Finding 1 (Employees)**: log in as EMPLOYEE, search a term matching another employee's name/code — assert no employee result is returned (expected to currently **fail** — results are currently returned)
- [ ] **Regression test for Finding 1 (Assets)**: log in as EMPLOYEE, search a term matching an asset not allocated to them — assert no result is returned (expected to currently **fail**)
- [ ] Log in as EMPLOYEE, search a term matching a Disposal record or Audit Log entry — assert no result is returned (should currently **pass** — these two categories are already correctly gated; keep as a regression guard)
- [ ] Repeat both regression tests for AUDITOR/ASSET_MANAGER/DEPARTMENT_HEAD to confirm the fix, once applied, matches each role's actual entitlement per its dedicated module (not a blanket EMPLOYEE-only fix)
- [ ] **Security**: confirm no SQL injection is possible via the `q` parameter across all entity blocks (should currently **pass**)
- [ ] **Functional**: a search matching multiple entity types returns correctly-categorized, correctly-linked results for a fully-privileged role (SUPER_ADMIN)

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 7 | Broad, useful cross-entity search |
| Lifecycle support | N/A | Not applicable |
| Data integrity | 6 | Search results are accurate to the underlying data; the issue is *who* can see them |
| UX | 7 | Clean, unified search experience across many entity types |
| Validation | 8 | Correct SQL parameterization throughout |
| RBAC | 3 | **Finding 1 is a genuine, confirmed access-control gap** — the clearest evidence in this entire audit that per-page RBAC correctness (verified repeatedly and thoroughly module-by-module) does not automatically guarantee cross-cutting features built on top of that data are equally scoped |
| Security | 4 | No injection risk, but the access-control bypass is a real confidentiality issue affecting two of the app's most sensitive entity types (personal employee data, organizational asset data) |
| API integration | 6 | Single-page implementation, no dedicated servlet — reasonable for this feature's scope |
| DB integrity | N/A | Read-only |
| Auditability | N/A | Reasonable scope decision not to log search queries |
| Reliability | 7 | Schema-adaptive coding handles missing columns/tables gracefully, consistent with the codebase's better modules |
| Performance | 7 | Reasonable per-category result caps |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Not applicable |

**Overall status: MAJOR WORK REQUIRED**

This module is a clean, well-built search feature undermined by a genuine, confirmed, and — notably — *inconsistently applied* access-control gap: the exact gating pattern needed already exists on the same page for two other categories, it simply wasn't applied to Assets and Employees. This is exactly the kind of cross-cutting gap that validates a full module-by-module audit methodology over spot-checking individual pages in isolation — no single-module review of Assets or Employees would have caught it, since both of those modules' own access control is, in fact, correct.
