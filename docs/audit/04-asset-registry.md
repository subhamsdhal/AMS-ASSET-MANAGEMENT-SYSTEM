# Module 4 Audit — Asset Registry (Assets)

**Scope:** Core asset master-record CRUD — list/search, add, edit, view, QR-code assignment at creation, optional document attach at creation. Disposal (a status-transition action reachable from here) is cross-referenced but deep-audited in Module 13.
**Verification layers used:** (a) static code reading — full for servlets/DAO. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Asset List | [assets.jsp](src/main/webapp/assets.jsp) | Searchable/filterable asset register, entry point for Add/Edit/View/Export |
| Add Asset | [add_asset.jsp](src/main/webapp/add_asset.jsp) | New asset intake form incl. optional photo + supporting document |
| Edit Asset | [edit_asset.jsp](src/main/webapp/edit_asset.jsp) | Edit master fields; status is deliberately not editable here (see §3) |
| View Asset | [view_asset.jsp](src/main/webapp/view_asset.jsp) | Read-only detail, QR generation entry point, document list |
| Asset Register Card | [asset_register_card.jsp](src/main/webapp/asset_register_card.jsp) | Printable register-card view |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| D1 | Add Asset submit | [add_asset.jsp](src/main/webapp/add_asset.jsp) form | native POST (multipart) | `POST /AddAssetServlet` | [AddAssetServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/AddAssetServlet.java:32) | `assets`, `asset_documents`, `asset_document_text_index`, `audit_logs` | Exhaustive: required fields, category-vendor active-mapping check ([AddAssetServlet.java:149](src/main/java/com/mycompany/asset_management_system_ams/AddAssetServlet.java:149)), duplicate asset-code/serial check, purchase-date not in future, warranty not before purchase, image-upload validation, optional document validation | FE/BE: `RoleAccessUtil.hasAccess()` explicitly re-checked in the servlet itself (not just relying on the filter) at [AddAssetServlet.java:56](src/main/java/com/mycompany/asset_management_system_ams/AddAssetServlet.java:56) → `assets.jsp?access=denied` on failure; matches `assetOps` (SUPER_ADMIN/ADMIN/ASSET_MANAGER) | Yes — every single rejection path (missing fields, bad dates, invalid vendor mapping, duplicate, bad file) writes its own `ADD_BLOCKED` audit row before redirecting, not just the success path ([AddAssetServlet.java:95,119,134,150,166,184](src/main/java/com/mycompany/asset_management_system_ams/AddAssetServlet.java:95)) — notably thorough | Yes — `NotificationEventService.sendAssetAddedNotice` ([AddAssetServlet.java:234](src/main/java/com/mycompany/asset_management_system_ams/AddAssetServlet.java:234)) | Redirects with `?error=failed/duplicate_code/invaliddate/invalidvendor/duplicate/invalidfile/server`; `?msg=added` / `?msg=added_doc_failed` on partial success | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | `qr_public_token` generated via `SecureRandom` at creation ([AssetDAO.java:147](src/main/java/com/mycompany/asset_management_system_ams/AssetDAO.java:147)) — code comments document this as a **prior fixed vulnerability** (predictable `IRAMS-<assetCode>` tokens were guessable and confirmed live on real assets before the fix); worth confirming during runtime verification that no asset in the live DB still carries a pre-fix predictable token |
| D2 | Live "Asset Code Available?" check | add_asset.jsp/edit_asset.jsp JS (AJAX on code field blur/input) | JS fetch | `GET /CheckAssetCodeServlet?assetCode=...` | [CheckAssetCodeServlet.doGet](src/main/java/com/mycompany/asset_management_system_ams/CheckAssetCodeServlet.java:16) | `assets` (read) | none needed (read-only availability check) | BE: requires a session with `user_id` set ([CheckAssetCodeServlet.java:26](src/main/java/com/mycompany/asset_management_system_ams/CheckAssetCodeServlet.java:26)) — but **`/CheckAssetCodeServlet` has no entry anywhere in `RoleAccessUtil.ROLE_MAP`** (confirmed by direct search of the file) | n/a | n/a | JS "only processes the response on status 200" per this servlet's own code comment describing an earlier, now-fixed bug of the identical shape | Code | **BROKEN** | **Medium-High** | **`RoleAuthorizationFilter` runs before this servlet is ever reached and calls `RoleAccessUtil.hasAccess(role, "/CheckAssetCodeServlet")`. Since this path has no entry in `ROLE_MAP`, `hasAccess()` falls through to its documented default-deny — which, per the class's own code comment and `RoleAccessUtilTest.testDefaultDenyForUnknownEndpoint`, applies even to SUPER_ADMIN. Every role, including Super Admin, gets a 403 from the filter before this servlet's own logic ever runs. Because the calling JS only handles HTTP 200 (a pattern this exact file's own comment says has silently broken this feature once already, for a different reason), the live "is this asset code already taken?" feedback on Add/Edit Asset silently never appears for anyone — no console error, no visible failure, the form simply behaves as if the check never ran. This does not block asset creation itself (the servlet-side `isAssetCodeExists`/`isDuplicateAssetCodeOrSerial` checks in `AddAssetServlet`/`UpdateAssetServlet` are the real enforcement and are unaffected), but the UX feature this control exists for is completely non-functional.** |
| D3 | Edit Asset submit | [edit_asset.jsp](src/main/webapp/edit_asset.jsp) form | native POST (multipart) | `POST /UpdateAssetServlet` | [UpdateAssetServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/UpdateAssetServlet.java:26) | `assets`, `audit_logs` | Same validation shape as D1, plus asset-must-exist check ([UpdateAssetServlet.java:110-115](src/main/java/com/mycompany/asset_management_system_ams/UpdateAssetServlet.java:110)) | Same as D1 | Yes — same thorough per-rejection-reason `UPDATE_BLOCKED` pattern | Yes — `sendAssetUpdatedNotice` | Same redirect-with-error-param convention | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **`asset_status` is explicitly excluded from the editable form** — the servlet always passes `existingAsset.getAssetStatus()` back into `updateAsset()` unchanged ([UpdateAssetServlet.java:206,222](src/main/java/com/mycompany/asset_management_system_ams/UpdateAssetServlet.java:206)) — correct separation of concerns: status transitions are forced through their own dedicated workflows (allocation/disposal/etc.), not this generic edit form. Old asset image is cleaned up on successful replacement ([UpdateAssetServlet.java:230-235](src/main/java/com/mycompany/asset_management_system_ams/UpdateAssetServlet.java:230)) — no orphaned-file leak observed here |
| D4 | View Asset (page load) | view_asset.jsp | page load | `GET view_asset.jsp?id=N` | inline JSP, `AssetDAO.getAssetById` | `assets` + joined lookups (read) | `id` parameterized | Role gate present (not fully re-read this pass; `RoleAccessUtil` maps `/view_asset.jsp` → `assetViewOps`, SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR/DEPARTMENT_HEAD) | n/a | n/a | Not assessed this pass for nonexistent id | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | — |
| D5 | Asset list search/filter/export | assets.jsp | mixed (some client JS, export is a real request) | export → `export_asset_report.jsp` (deep-audited in Module 24) | — | `assets` (read) | — | `canManageAssets` flag on the page gates Add/Edit buttons; `RoleAccessUtil` maps the page to `assetViewOps` for viewing | n/a | n/a | Not assessed | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | — |

No "Delete Asset" control exists anywhere in the codebase (confirmed — no `DeleteAssetServlet` file) — correct lifecycle design for an AMS: assets are never hard-deleted, only transitioned to `DISPOSED` via the dedicated disposal workflow (Module 13), preserving full history.

---

## 3. Business Workflow / Lifecycle Check

- **Registration**: Add Asset requires an *active* category↔vendor mapping to exist before an asset can be created under that combination ([AssetDAO.isActiveSupplierMappedToCategory](src/main/java/com/mycompany/asset_management_system_ams/AssetDAO.java:118), also independently re-checked in the servlet at [AddAssetServlet.java:149](src/main/java/com/mycompany/asset_management_system_ams/AddAssetServlet.java:149) before the DAO call — belt-and-braces, both layers enforce it) — this is a genuine cross-module lifecycle dependency (Category-Vendor Mapping module gates Asset Registry) worth carrying into the Phase 2 cross-module trace.
- **Status is not settable via this module's own CRUD** — `AVAILABLE` at creation, and `UNCHANGED` on every subsequent edit through this module; all other statuses (`ALLOCATED`, `UNDER_MAINTENANCE`, `DISPOSED`, `LOST`, `DAMAGED`) are the responsibility of Modules 5/10/13 and whatever else transitions them. This module correctly does not offer a bypass.
- **Disposal precondition** (reached from `AssetDAO.disposeAsset`, cross-referenced here since it lives in this DAO): blocks disposing an asset that's already `DISPOSED`, has an active allocation, or already has an existing disposal record ([AssetDAO.java:300-308](src/main/java/com/mycompany/asset_management_system_ams/AssetDAO.java:300)) — correct guard against double-disposal or disposing a currently-assigned asset out from under its custodian. **Finding for Module 13 to verify**: the single-argument convenience overload `disposeAsset(int assetId)` ([AssetDAO.java:275-284](src/main/java/com/mycompany/asset_management_system_ams/AssetDAO.java:275)) hardcodes `approvedBy = 1` — if any live caller uses this overload instead of the full 6-argument version (which takes a real `approvedBy`), every disposal through that path would misattribute approval to user ID 1 regardless of who actually triggered it. Flagging for Module 13's own audit to confirm which overload `DisposeAssetServlet` actually calls.
- **Serial number / asset code immutability**: both are editable via `edit_asset.jsp`/`UpdateAssetServlet` (re-validated for uniqueness on every edit) — this is a reasonable real-world allowance (correcting a data-entry typo after the fact) but means an asset's "permanent" identifiers aren't actually permanent; nothing in the audit trail's `action_details` free text is confirmed (this pass) to capture the specific old-code→new-code diff distinctly from the rest of the update, which would matter if an asset code is ever referenced externally (e.g. printed on a physical tag) before being changed — cross-reference Module 8 (QR/Barcode) for whether a changed asset code desyncs a previously-printed physical label.

---

## 4. Data Model Check

`assets` ([schema.sql:244-285](schema.sql:244)): `asset_id, asset_code, asset_name, category_id, vendor_id, serial_number, model_number, purchase_date, purchase_cost, warranty_expiry, department_id, division_id, location_id, location, asset_status (enum), condition_status (enum), service_status (enum), last_physical_verification_date, qr_code, qr_public_token, asset_image_path, depreciation_rate, remarks, created_by, updated_by, created_at, updated_at`.

- Solid, appropriately-normalized field set for a railway/enterprise AMS: three independent status dimensions (`asset_status`/`condition_status`/`service_status`) rather than one overloaded field, dual location representation (`location_id` FK to a proper `railway_locations` table + a free-text `location` fallback — `getAssetById`'s query `COALESCE(l.location_name, a.location, 'Rail Sadan')` shows the free-text field is a deliberate fallback for assets not yet mapped to a structured location, not dead weight).
- **`model_number` exists on the table but was not referenced anywhere in `AddAssetServlet`/`UpdateAssetServlet`'s parameter lists or `AssetDAO.addAsset`/`updateAsset`'s SQL** in the code read this pass — appears to be a column with no write path from the two primary CRUD servlets (worth confirming during runtime UI check whether `add_asset.jsp`/`edit_asset.jsp` even render a Model Number field, or whether this is a genuinely orphaned/unused column).
- **No `insurance_policy_number`/`insurance_expiry` fields** — for a public-sector railway asset register, insurance tracking is a common enterprise expectation; not present here (flag in §8/§9, may partially exist in Warranty module instead, to cross-check).
- **No `custodian`/`current_holder` column on `assets` itself** — correctly normalized out to `asset_allocation` (Module 5) rather than duplicated here; confirmed no redundant/conflicting copy of "who has this" on the asset row itself.
- `purchase_cost` is `decimal(12,2)` (appropriate for currency, avoids float rounding issues) — good practice, consistent across the schema wherever money is stored (spot-checked here, worth confirming as a pattern in Modules with heavier financial data like Disposal/Warranty).
- `qr_public_token` is `NOT NULL` with a `UNIQUE KEY` — correctly enforced at the DB layer, not just application-level, matching the `SecureRandom` generation fix noted in D1.

---

## 5. Status Model Check

- `asset_status` enum: `AVAILABLE, ALLOCATED, UNDER_MAINTENANCE, DISPOSED, LOST, DAMAGED` — a flat set with no explicit state-machine table anywhere in this module (transition legality is enforced ad-hoc, one guard at a time, in each module that triggers a transition — e.g. `disposeAsset`'s guard against disposing an already-`DISPOSED` or actively-allocated asset). This module itself never writes anything other than `AVAILABLE` (creation) or an unchanged pass-through (edit), so no illegal transition is possible *from here*; the state machine's real integrity depends on every other module (Allocation, Maintenance, Disposal, Physical Verification) enforcing its own legal-transition rules correctly — to be assessed per-module rather than assumed here.
- **Potential impossible-state risk flagged for cross-module verification**: nothing observed in this module prevents an asset's `asset_status='ALLOCATED'` from persisting after that asset is disposed, *if* the disposing code path were ever reached without going through `AssetDAO.disposeAsset`'s guard (e.g., a hypothetical future direct SQL update, or the single-arg overload bypassing the real approval attribution noted in §3) — the guard exists and is well-written, but it is the **only** thing preventing a disposed-while-allocated impossible state; there is no DB-level CHECK constraint or trigger backing it up. Flag for Module 5 (Allocation) and Module 13 (Disposal) to jointly confirm no other write path to `asset_status='DISPOSED'` bypasses this guard.

---

## 6. RBAC & Security Check

- **CSRF**: same app-wide gap — no tokens on Add/Edit Asset forms. Both require ASSET_MANAGER-or-above session, no secondary re-authentication, making them CSRF-susceptible in principle (a malicious page could silently add or modify an asset record via a tricked admin session) — consistent with every other module's forms so far, not re-scored per-module beyond noting it recurs.
- **RBAC enforcement**: double-layered as usual (filter + explicit in-servlet `RoleAccessUtil.hasAccess()` re-check) for Add/Edit — a genuinely defensive pattern seen consistently across every servlet read in this codebase so far.
- **Finding (Medium-High, functional not security)**: `/CheckAssetCodeServlet`'s missing `ROLE_MAP` entry (D2) is a broken-feature finding, not a security hole — if anything it's over-restrictive (denies everyone) rather than under-restrictive, so it poses no access-control risk, only a UX regression.
- **IDOR**: `assetId`/`id` parameters are used directly in parameterized queries with no ownership scoping beyond role — appropriate, since assets aren't user-owned records in this system (they belong to the organization; access is role-gated, not owner-gated), so an ASSET_MANAGER viewing/editing any `assetId` is by design, not a defect.
- **File upload validation**: `AssetImageUploadUtil`/`AssetDocumentUploadUtil` were not read in full this pass (deep dive belongs to Module 21, Document Vault) — flagged as a cross-reference; `AddAssetServlet`/`UpdateAssetServlet` do catch and audit-log upload-specific exceptions distinctly from other validation failures, a good sign of deliberate handling rather than a generic catch-all.

---

## 7. Audit Log & Data Integrity Check

- Exceptionally thorough for this module specifically: **every single validation-rejection branch** in both `AddAssetServlet` and `UpdateAssetServlet` writes its own distinctly-worded `ADD_BLOCKED`/`UPDATE_BLOCKED` audit row before redirecting (6 distinct rejection reasons each, all logged) — this is materially better security-monitoring coverage than a module that only logs successful actions, since it creates a paper trail of *attempted* invalid/blocked actions too (useful for detecting probing/misuse patterns, consistent with `audit_logs.jsp`'s dedicated "Blocked / Denied" KPI tile from Module 3).
- Successful Add/Update both log a single consolidated `action_details` string covering asset code, name, category, vendor, and (for Add) initial status — reasonably informative for a free-text field, though still not a structured diff (same limitation noted in Modules 1-3).
- No integrity concern found beyond the general app-wide `role_id`/schema-drift and audit-immutability findings already covered in Modules 1-3 (not re-litigated here).

---

## 8. Missing Features / Gaps

- **`/CheckAssetCodeServlet` is non-functional for everyone** (D2) — straightforward one-line fix (add a `ROLE_MAP` entry matching `assetOps` or broader, since it's a read-only availability check safe for any authenticated role that can reach the Add/Edit Asset forms).
- **No visible write path for `model_number`** from the two primary CRUD servlets — confirm during runtime check whether this is a dead column or whether the JSP form fields exist but weren't traced to a servlet parameter in this pass.
- **No insurance tracking fields** on the asset record.
- **No bulk-import (CSV/Excel) path** identified in this module's own servlet set — cross-check Module 24 (Reports & Exports) for whether an import counterpart to the export feature exists; if not, this is a real gap for onboarding a large existing asset fleet into the system.
- **No soft "asset photo gallery"** (multiple images) — `asset_image_path` is a single column, one photo per asset only.

---

## 9. Advanced Feature Recommendations

- **P0** — Fix `/CheckAssetCodeServlet`'s missing `RoleAccessUtil` entry.
- **P1** — CSRF tokens on Add/Edit Asset (shared recommendation, app-wide).
- **P1** — Confirm and either wire up or remove the apparently-orphaned `model_number` column.
- **P2** — Bulk asset import (CSV/Excel) with the same validation rules as the single-add path, for fleet onboarding.
- **P2** — Insurance policy tracking fields, if not already covered elsewhere (cross-check Warranty module).
- **P3** — Multi-photo gallery per asset.
- **P3** — DB-level CHECK constraint or trigger backing the "no disposal of an actively-allocated asset" rule, as defense-in-depth beyond the application-layer guard in `AssetDAO.disposeAsset`.

---

## 10. Test Cases

[AssetDAOTest.java](src/test/java/com/mycompany/asset_management_system_ams/AssetDAOTest.java) exists in the Phase-0 inventory (not yet read in full this pass) — flag to confirm its actual coverage against the checklist below in a later pass.

- [ ] **Functional**: valid Add Asset with all fields succeeds, creates one `assets` row with `asset_status='AVAILABLE'` and a unique `qr_public_token`
- [ ] Add Asset with an optional document attached creates both the `assets` row and a linked `asset_documents` row with correct `asset_id`
- [ ] Edit Asset preserves `asset_status` unchanged regardless of what (if anything) is submitted for it
- [ ] **Negative/Boundary**: Add Asset with a category/vendor pair that has no *active* `category_vendor_mapping` row is rejected with `ADD_BLOCKED` logged
- [ ] Add/Edit Asset with a duplicate `asset_code` or `serial_number` (across all other assets) is rejected
- [ ] Add/Edit Asset with `purchaseDate` in the future, or `warrantyExpiry` before `purchaseDate`, is rejected
- [ ] **Regression test for D2**: `GET /CheckAssetCodeServlet` as any authenticated role currently returns 403 from the filter — assert this changes to 200 once the `ROLE_MAP` fix lands
- [ ] **RBAC**: EMPLOYEE/AUDITOR/DEPARTMENT_HEAD directly POSTing to `AddAssetServlet`/`UpdateAssetServlet` is denied
- [ ] **Security**: direct `curl -X POST /AddAssetServlet` with a valid ASSET_MANAGER session and no CSRF-equivalent token succeeds (documents the shared CSRF gap)
- [ ] Upload a file disguised as an image (wrong magic bytes/extension mismatch) to the asset-photo field — confirm `AssetImageUploadUtil` rejects it (deep validation lives in Module 21, but the entry point is here)
- [ ] **Concurrency**: two simultaneous Add Asset submissions with the same `assetCode` — confirm the DB's `UNIQUE KEY uk_assets_asset_code` is the real backstop (not just the pre-check `isAssetCodeExists`, which has a TOCTOU race window between check and insert)
- [ ] **DB integrity**: attempt to insert an `assets` row directly via SQL with `asset_status` outside the enum's allowed values — confirm the enum constraint rejects it at the DB layer
- [ ] **API**: `disposeAsset(assetId)` single-arg overload's hardcoded `approvedBy=1` — confirm (in Module 13) whether any live code path actually calls this overload, and if so, correct the attribution

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 8 | Core CRUD is thorough and well-validated; one confirmed broken AJAX convenience feature (D2) |
| Lifecycle support | 8 | Correct separation of status transitions from generic edit; no hard-delete; disposal precondition guards are solid |
| Data integrity | 7 | Strong DB constraints (unique code/token/serial, appropriate decimal types); orphaned `model_number` column and no insurance fields |
| UX | 7 | Consistent error/success redirect convention; the broken live-code-check silently degrades the add/edit form's UX |
| Validation | 9 | Genuinely the most thoroughly-validated servlet pair reviewed so far in this audit — six distinct, individually-audited rejection paths each |
| RBAC | 8 | Consistent double-layered enforcement; the one gap found (D2) is over-restrictive, not under-restrictive |
| Security | 6 | No CSRF protection (shared app-wide gap); otherwise solid — notably, a real predictable-token vulnerability was already found and fixed here in a prior pass |
| API integration | 8 | Clean, consistent servlet design |
| DB integrity | 8 | Strong constraint usage; guard logic for disposal preconditions is application-layer only, no DB-level backstop |
| Auditability | 9 | Best-in-class so far — every rejection reason, not just successes, is individually logged |
| Reliability | 7 | Defensive coding throughout; upload-failure cleanup (deleting orphaned uploaded files on a later validation failure) shows real attention to partial-failure states |
| Performance | 6 | `getNextSystemAssetCode()` scans all `AST%`-prefixed codes into memory to compute the next number — will not scale gracefully with fleet size, though not urgent at current scale |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Covered under Module 24 |

**Overall status: MINOR WORK REQUIRED**

This is the strongest-engineered module audited so far — validation depth, audit-log granularity, and defensive RBAC re-checks are all genuinely production-grade. The one concrete defect found (D2, a fully broken but non-critical convenience feature) is a quick fix. The larger open risks it inherits (schema drift, no CSRF, no DB-level backstop for the disposal guard) are shared findings already tracked at the app-wide level rather than unique to this module.
