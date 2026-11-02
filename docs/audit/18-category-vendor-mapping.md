# Module 18 Audit — Category–Vendor Mapping

**Scope:** Which vendors are eligible suppliers for which asset categories — a small but load-bearing module, since Module 4 confirmed `AddAssetServlet` requires an *active* mapping to exist before an asset can be created (`AddCategoryVendorMappingServlet`, `CategoryVendorMappingAjaxServlet`, `UpdateCategoryVendorMappingStatusServlet`, `CategoryVendorMappingDAO`).
**Verification layers used:** (a) static code reading — full. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Category-Vendor Mapping | [category_vendor_mapping.jsp](src/main/webapp/category_vendor_mapping.jsp) | List, create, enable/disable mappings |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| R1 | Add / Reactivate Mapping | category_vendor_mapping.jsp form | native POST | `POST /AddCategoryVendorMappingServlet` | [AddCategoryVendorMappingServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/AddCategoryVendorMappingServlet.java:21) | `category_vendor_mapping`, `audit_logs` | category+vendor IDs required; correctly distinguishes "already active" (blocked with a specific `msg=duplicate`) from "exists but inactive" (silently reactivated instead of erroring, a sensible UX choice) | SUPER_ADMIN/ADMIN/ASSET_MANAGER | Yes | Unescaped (same cross-cutting gap, 6th confirmed module) | `?error=invalid/failed/server`, `?msg=duplicate/reactivated/mapped` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | `UNIQUE KEY uq_category_vendor (category_id, vendor_id)` at the DB layer backs the application-level active/inactive check — good defense-in-depth against a race between the status check and the write |
| R2 | Enable/Disable Mapping (page action) | category_vendor_mapping.jsp row action | native POST/GET | `POST /UpdateCategoryVendorMappingStatusServlet` | [UpdateCategoryVendorMappingStatusServlet.process](src/main/java/com/mycompany/asset_management_system_ams/UpdateCategoryVendorMappingStatusServlet.java:32), reachable from **both** `doGet` and `doPost` | `category_vendor_mapping`, `audit_logs` | mappingId + action required | SUPER_ADMIN/ADMIN/ASSET_MANAGER | Yes | Unescaped | `?error=invalid/failed/server`, `?msg=updated` | Code | **PARTIALLY WORKING — see Finding 1** | **Medium-High** | **This servlet explicitly registers `doGet()` calling the exact same `process()` method as `doPost()` ([UpdateCategoryVendorMappingStatusServlet.java:21-30](src/main/java/com/mycompany/asset_management_system_ams/UpdateCategoryVendorMappingStatusServlet.java:21)) — a state-changing action (enable/disable a category-vendor mapping) is reachable via a plain GET request, with no client-side confirmation of any kind at this layer.** |
| R3 | Enable/Disable Mapping (AJAX variant) | category_vendor_mapping.jsp (JS) | AJAX POST | `POST /CategoryVendorMappingAjaxServlet` | [CategoryVendorMappingAjaxServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/CategoryVendorMappingAjaxServlet.java:19) | `category_vendor_mapping`, `audit_logs` (not fully re-traced) | mappingId + action required, returns JSON | SUPER_ADMIN/ADMIN/ASSET_MANAGER, JSON error responses with correct HTTP status codes (401/403) rather than redirects — appropriate for an AJAX endpoint | Not fully re-traced | Not fully re-traced | JSON `{"success":false,"error":"..."}` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Correctly POST-only, no GET handler registered — this AJAX sibling of R2 does **not** share R2's vulnerability |

### Finding 1 (Medium-High) — A live, unfixed instance of the exact GET-state-change vulnerability class already found and fixed in five sibling modules

This is the most notable finding in this module, precisely *because* of what's absent: `UpdateCategoryVendorMappingStatusServlet` has no code comment acknowledging or explaining a GET handler — unlike `DisableEmployeeServlet` (Module 9), `DeleteEmployeeServlet` (Module 9), `DeleteDepartmentServlet` (Module 15), `UpdateCategoryStatusServlet` (Module 16), and `DeleteVendorServlet` (Module 17), which **all** carry explicit, detailed comments documenting that they used to accept `doGet()` and were deliberately fixed to reject it, each one citing the same vulnerability shape (a bare `<a href>`/`<img>` tag, browser link-prefetch, or a crawler visiting the URL could silently trigger the state change for any logged-in privileged user who has it loaded). **This module's equivalent action was never included in that fix sweep.** `GET /UpdateCategoryVendorMappingStatusServlet?mappingId=N&action=disable` today would successfully disable a category-vendor mapping for any SUPER_ADMIN/ADMIN/ASSET_MANAGER whose browser is induced to issue that request — via a crafted link, an embedded image tag on a malicious or compromised page, a browser prefetch, or a crawler — with zero user interaction beyond having the URL loaded while authenticated. Given the direct downstream consequence (Module 4: disabling a mapping blocks new asset creation under that category+vendor combination), this is a real, currently-live, moderately-consequential finding — not merely a historical curiosity like the other five instances, all of which are already closed.

---

## 3. Business Workflow / Lifecycle Check

- **Add-or-reactivate logic is a nice, deliberate UX choice**: rather than erroring on "this mapping already exists (inactive)," the servlet transparently reactivates it and tells the user so (`msg=reactivated` vs. `msg=mapped`) — avoids forcing an admin to hunt down and separately re-enable a previously-disabled mapping instead of just re-adding it.
- **Direct downstream dependency on Module 4**: this module is small but structurally important — it's the single gate Module 4's `AddAssetServlet`/`UpdateAssetServlet` both check before allowing an asset to be created/edited under a given category+vendor pair. Finding 1's exposure therefore has a real, if modest, blast radius: an attacker exploiting it couldn't create or modify data directly, but could disrupt legitimate asset-management operations (silently blocking new asset intake for a specific category/vendor combination) as a low-grade denial-of-service, deniable as "just a bug" since the action itself looks like routine admin activity in the audit log.

---

## 4. Data Model Check

`category_vendor_mapping` ([schema.sql:368-378](schema.sql:368)): `mapping_id, category_id, vendor_id, status (varchar, not enum — same "compensated by application-layer whitelist only" pattern noted for `maintenance_requests` in Module 11, though here the value set is simpler, just ACTIVE/INACTIVE), created_at, updated_at`. `UNIQUE KEY (category_id, vendor_id)` correctly prevents duplicate mapping rows for the same pair — good, simple, well-constrained schema.

---

## 5. Status Model Check

Simple `ACTIVE`/`INACTIVE` toggle, correctly enforced with the add-or-reactivate pattern preventing duplicate rows. No impossible-state risk found.

---

## 6. RBAC & Security Check

- **Finding 1 is this module's headline security issue.**
- **CSRF**: app-wide gap; notably, Finding 1 actually makes this module's exposure *worse* than the typical CSRF gap elsewhere, since a GET-based trigger doesn't even need a forged form submission — a bare link or image tag suffices.
- RBAC role-gating itself is otherwise correct and consistent across all three servlets.

---

## 7. Audit Log & Data Integrity Check

- Both add and status-change actions are logged correctly (and would still be logged even when triggered via the GET vulnerability, meaning the audit trail would show the disabling admin's account as the actor — accurate as far as attribution goes, but wouldn't indicate the action was involuntary/triggered by a third party).
- No other integrity concerns found.

---

## 8. Missing Features / Gaps

- **Finding 1**: live GET-state-change vulnerability.
- Unescaped email HTML (cross-cutting).

---

## 9. Advanced Feature Recommendations

- **P0** — Remove the `doGet()` override (or make it redirect to a confirmation page rather than performing the action, matching the pattern `DisposeAssetServlet`'s `doGet()` correctly uses in Module 13) from `UpdateCategoryVendorMappingStatusServlet` — this is a direct, mechanical fix using the exact pattern already proven and applied five times elsewhere in this codebase; flagging as P0 rather than P1 specifically because every sibling instance of this bug was treated as worth fixing immediately when found.
- **P1** — Apply `HtmlEscapeUtil.escape()` to this module's email bodies (shared cross-cutting fix).
- **P3** — CSRF tokens (shared app-wide recommendation).

---

## 10. Test Cases

No dedicated test file found for this module in the Phase-0 inventory.

- [ ] **Regression test for Finding 1 (highest priority in this module)**: issue a plain `GET /UpdateCategoryVendorMappingStatusServlet?mappingId=N&action=disable` with a valid ASSET_MANAGER session cookie (no form submission, no POST body) — assert the mapping is **not** disabled (expected to currently **fail** — it currently succeeds)
- [ ] Compare against `CategoryVendorMappingAjaxServlet` (R3) — confirm the equivalent `GET` attempt against that endpoint correctly does nothing (no `doGet` registered), establishing R3 as the reference-correct sibling
- [ ] **Functional**: adding a mapping for a previously-inactive pair reactivates it rather than erroring or creating a duplicate row
- [ ] Adding a mapping for an already-active pair is blocked with `msg=duplicate`
- [ ] **RBAC**: EMPLOYEE/AUDITOR/DEPARTMENT_HEAD cannot reach any of the three servlets
- [ ] **DB integrity**: attempt a direct duplicate insert into `category_vendor_mapping` for an existing `(category_id, vendor_id)` pair — confirm the `UNIQUE KEY` rejects it
- [ ] **Cross-module regression**: disable a mapping, then attempt to add an asset under that category+vendor via Module 4's `AddAssetServlet` — confirm it's correctly blocked (`error=invalidvendor`)

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 8 | Small, complete, well-scoped module |
| Lifecycle support | 8 | Add-or-reactivate is a genuinely thoughtful UX/data-integrity choice |
| Data integrity | 8 | Good UNIQUE constraint, no orphaned/dead fields found |
| UX | 7 | Clear, specific messaging for the reactivate-vs-new-mapping distinction |
| Validation | 7 | Adequate |
| RBAC | 7 | Correct role-gating, undermined by Finding 1's method-level gap |
| Security | 4 | **Finding 1 is a real, currently-unfixed instance of a vulnerability class this exact codebase has already found and fixed five times elsewhere** — the clearest "the fix pattern is known but wasn't applied everywhere" evidence in the whole audit series |
| API integration | 7 | Consistent conventions; R3's AJAX error handling (proper HTTP status codes) is a nice touch |
| DB integrity | 8 | Good constraint usage |
| Auditability | 7 | Adequate logging, correctly attributes even a GET-triggered action to the visiting account |
| Reliability | 7 | No concurrency-sensitive logic beyond the UNIQUE-constraint backstop |
| Performance | 8 | Simple, lightweight module |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Covered under Module 24 |

**Overall status: MINOR WORK REQUIRED**

This module is otherwise clean and well-built, but Finding 1 is a genuinely important catch for the final report: it demonstrates that even a security-hardening pass explicitly repeated five times across sibling modules can still miss an instance sitting right next to them, and is exactly the kind of finding a systematic, methodical module-by-module audit (rather than spot-checking) is supposed to catch.
