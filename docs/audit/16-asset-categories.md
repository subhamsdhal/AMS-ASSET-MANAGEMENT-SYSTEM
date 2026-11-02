# Module 16 Audit — Asset Categories

**Scope:** Category master-data CRUD (`AddCategoryServlet`, `UpdateCategoryServlet`, `UpdateCategoryStatusServlet`, `CategoryDAO`). No delete action exists for categories anywhere in the codebase (confirmed by file listing) — enable/disable is the only lifecycle action beyond create/edit, making this an inherently lower-risk module than most others audited so far.
**Verification layers used:** (a) static code reading — full. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Category List | [categories.jsp](src/main/webapp/categories.jsp) | List, entry point, Export |
| Add Category | [add_category.jsp](src/main/webapp/add_category.jsp) | Create |
| Edit Category | [edit_category.jsp](src/main/webapp/edit_category.jsp) | Update name/description/status |
| View Category | [view_category.jsp](src/main/webapp/view_category.jsp) | Read-only detail |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| P1 | Add Category | [add_category.jsp](src/main/webapp/add_category.jsp) form | native POST | `POST /AddCategoryServlet` | [AddCategoryServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/AddCategoryServlet.java:21) | `asset_categories`, `audit_logs` | name + description required, duplicate name blocked at the DB layer (`UNIQUE KEY uk_asset_categories_name`, surfaced as a generic `ADD_BLOCKED`/`error=failed` rather than a specific "duplicate name" message — a minor UX rough edge, functionally correct) | SUPER_ADMIN/ADMIN/ASSET_MANAGER, matches `assetOps` | Yes — both success and the duplicate-name block | **No** — `categoryName`/`description` interpolated unescaped into the HTML email body ([AddCategoryServlet.java:60-62](src/main/java/com/mycompany/asset_management_system_ams/AddCategoryServlet.java:60)) | `?error=failed/server` | Code | **CODE LOOKS CORRECT, BUT unescaped email — see Finding 1** | Medium | Confirms the cross-cutting `HtmlEscapeUtil` gap (already tracked since Module 10) extends to this module too — Categories did not receive the fix that Disposal/Employees/Departments did |
| P2 | Edit Category | edit_category.jsp | native POST | `POST /UpdateCategoryServlet` | not fully re-traced this pass | `asset_categories`, `audit_logs` | — | assetOps | — | — | — | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Calls `CategoryDAO.updateCategory()`, which only ever touches `category_name`/`description`/`status`/`is_active` — see Finding 2 |
| P3 | Enable / Disable Category | categories.jsp row action | native **POST** | `POST /UpdateCategoryStatusServlet` | [UpdateCategoryStatusServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/UpdateCategoryStatusServlet.java:30) | `asset_categories`, `audit_logs` | id + action required | assetOps | Yes | Unescaped (same pattern) | `?error=invalid/failed/server` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **This servlet's own code comment is the confirmed, direct source of the GET→POST fix chain cross-referenced by Employees (Module 9), Departments (Module 15), and `resolve_maintenance.jsp`** — explicitly documents the same vulnerability class (state change via `doGet()`, exploitable via a bare `<img>` tag, crawler prefetch, or browser link-prefetch) and its fix here. No dependency check is needed for this action (unlike Delete-style actions elsewhere) since disabling a category doesn't destroy anything — a genuinely low-risk, appropriately-scoped action |

### Finding 1 (Medium) — Unescaped HTML in category-management emails

Restated: neither `AddCategoryServlet` nor (by the same pattern, presumptively) `UpdateCategoryStatusServlet` apply `HtmlEscapeUtil.escape()` to user-supplied category name/description before embedding them in HTML email bodies — the same cross-cutting gap already tracked since Module 10, now confirmed present in a fourth module.

### Finding 2 (Low) — `useful_life_years`/`default_depreciation_rate` are permanently hardcoded and unreachable through any UI action

`asset_categories` has dedicated columns for a category-level default useful life (`useful_life_years`) and depreciation rate (`default_depreciation_rate`) — presumably intended to pre-fill or default these values when an asset of that category is created (Module 4 confirmed `assets.depreciation_rate` is a genuine, per-asset field collected on Add Asset). However: `CategoryDAO.addCategoryAndReturnId()` hardcodes these to `5` and `0.00` respectively for **every** category ever created ([CategoryDAO.java:102-104](src/main/java/com/mycompany/asset_management_system_ams/CategoryDAO.java:102)), and `CategoryDAO.updateCategory()` — the *only* other write path to this table — never includes either column in its `UPDATE` ([CategoryDAO.java:139-145](src/main/java/com/mycompany/asset_management_system_ams/CategoryDAO.java:139)). **There is no code path anywhere in the application that can ever change these values away from their hardcoded defaults, for any category, at any time.** This is a stronger version of the "schema models it, write path doesn't populate it" pattern seen repeatedly in this audit (Modules 5, 6, 9) — here the columns aren't just unpopulated at creation, they are **entirely unreachable**, permanently identical across every category in the system. If any reporting/depreciation-calculation feature (Module 24, not yet audited) relies on category-level depreciation defaults to differentiate, say, IT equipment from heavy rail machinery, it currently cannot — every category looks identical on this dimension.

---

## 3. Business Workflow / Lifecycle Check

- **No delete action exists for categories** — the safer "deactivate only" model this audit recommended for Departments (Module 15) is already how Categories works by default, likely because a category, once assigned to any asset, cannot be safely removed without breaking that FK relationship, and the developers simply never built a delete path rather than building one with guards. Good outcome either way.
- **Two overlapping status columns again**: `status` (`ACTIVE`/`INACTIVE`) and `is_active` (`YES`/`NO`) on `asset_categories` ([schema.sql:38-39](schema.sql:38)) — the exact same redundant-status-column pattern already flagged in Module 9 (Employees). Both are always written together by both `updateCategory()` and `updateCategoryStatus()`, so they can't currently drift from each other through the code paths read this pass, but it's the second confirmed instance of this specific schema smell, worth calling out as a recurring pattern for the final report rather than a one-off.
- **Category-Vendor mapping dependency** (Module 4 confirmed `AddAssetServlet` requires an *active* mapping between category and vendor before an asset can be created) means disabling a category has a real downstream effect (new assets under that category+any vendor become unavailable to add) without the disabling action itself needing to check anything — the consuming module (Assets) already enforces the constraint at the point of use, a reasonable "check at the point of consequence, not at the point of change" design.

---

## 4. Data Model Check

`asset_categories` ([schema.sql:32-44](schema.sql:32)): `category_id, category_name (UNIQUE), description, useful_life_years, default_depreciation_rate, status (enum), is_active (enum), created_at, updated_at`. Finding 2 is the main data-model concern; otherwise clean and appropriately constrained.

---

## 5. Status Model Check

Simple two-state (effectively, given the redundant column pair) active/inactive toggle, no complex transitions, no impossible-state risk.

---

## 6. RBAC & Security Check

- **CSRF**: app-wide gap; low incremental risk here specifically since none of this module's actions are destructive/irreversible (no delete, and disable is trivially reversible via a second click).
- **RBAC enforcement**: correct and consistent.
- **GET→POST fix**: confirmed at its source in this module (§2/P3) — valuable corroborating evidence for how many modules received this specific fix (now confirmed: Categories, Employees, Departments, and `resolve_maintenance.jsp`/Maintenance — a real, if partial, security-hardening sweep).

---

## 7. Audit Log & Data Integrity Check

- Both success and the duplicate-name rejection are logged on Add; Enable/Disable is logged.
- Finding 2 is the data-integrity item of note — permanently dead columns rather than an active bug.

---

## 8. Missing Features / Gaps

- **Finding 1**: unescaped email HTML (cross-cutting).
- **Finding 2**: `useful_life_years`/`default_depreciation_rate` are unreachable through any UI action.
- Duplicate-category-name rejection surfaces as a generic error rather than a specific "this name is taken" message.
- Redundant `status`/`is_active` column pair (cross-cutting pattern, also seen in Module 9).

---

## 9. Advanced Feature Recommendations

- **P1** — Expose `useful_life_years`/`default_depreciation_rate` on the Add/Edit Category forms and wire them into `CategoryDAO`'s INSERT/UPDATE, if category-level depreciation defaults are meant to be a real feature (confirm intent first — they may simply be vestigial from an earlier design that was superseded by per-asset depreciation rates, in which case removing the dead columns is the better fix).
- **P1** — Apply `HtmlEscapeUtil.escape()` to this module's email bodies (shared cross-cutting fix).
- **P2** — Surface a specific duplicate-name error message instead of the generic `error=failed`.
- **P3** — Consolidate the redundant `status`/`is_active` columns (cross-cutting, shared with Module 9's finding).
- **P3** — CSRF tokens (shared app-wide recommendation, low incremental priority for this specific module).

---

## 10. Test Cases

No dedicated test file found for this module in the Phase-0 inventory.

- [ ] **Functional**: creating a category with a unique name succeeds; duplicate name is rejected
- [ ] Editing a category's name/description/status persists correctly
- [ ] Enable/Disable toggles both `status` and `is_active` together, never leaving them disagreeing
- [ ] **Regression test for Finding 2**: attempt to set `useful_life_years`/`default_depreciation_rate` to a non-default value via the Edit form — confirm it currently has no effect (documents the current, likely-unintended behavior)
- [ ] **Regression test for Finding 1**: submit a category name/description containing HTML/script tags — assert the resulting email is escaped (expected to currently **fail**)
- [ ] **RBAC**: EMPLOYEE/AUDITOR/DEPARTMENT_HEAD cannot POST to any of the three servlets
- [ ] Confirm a plain `GET /UpdateCategoryStatusServlet?id=N&action=disable` does not disable the category (regression check for the already-fixed vulnerability)
- [ ] **DB integrity**: `uk_asset_categories_name` UNIQUE constraint holds under a direct duplicate insert attempt

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 7 | Core CRUD complete; category-level depreciation defaults are dead weight |
| Lifecycle support | 8 | No-delete/deactivate-only is the right model, achieved here by default |
| Data integrity | 6 | Finding 2's unreachable columns and the redundant status-column pair |
| UX | 7 | Generic duplicate-name error is a minor rough edge |
| Validation | 7 | Adequate for this module's low complexity |
| RBAC | 8 | Correct, consistent |
| Security | 6 | Unescaped email HTML (Finding 1); GET→POST fix confirmed and correctly applied here |
| API integration | 7 | Consistent conventions |
| DB integrity | 7 | Good UNIQUE constraint; dead columns drag this down slightly |
| Auditability | 7 | Adequate logging on all three actions |
| Reliability | 7 | No concurrency-sensitive logic in this module to stress-test |
| Performance | 8 | Simple, lightweight module, no inefficiencies |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Covered under Module 24 |

**Overall status: MINOR WORK REQUIRED**

A low-complexity, low-risk module overall (no destructive actions exist), with two straightforward, well-understood findings — the cross-cutting email-escaping gap and a set of permanently-dead depreciation-default columns — neither of which threatens data integrity or security in a serious way. Also valuable as the confirmed origin point for the GET→POST security fix cross-referenced by three other modules in this audit.
