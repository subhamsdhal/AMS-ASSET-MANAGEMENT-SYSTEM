# Module 17 Audit — Vendors / Suppliers

**Scope:** Vendor master-data CRUD (`AddVendorServlet`, `UpdateVendorServlet`, `DeleteVendorServlet`, `VendorDAO`). Document vault (`UploadVendorDocumentServlet`/`DownloadVendorDocumentServlet`) is cross-cutting, deep-audited in Module 21.
**Verification layers used:** (a) static code reading — full. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Vendor List | [vendors.jsp](src/main/webapp/vendors.jsp) | List, entry point |
| Add Vendor | [add_vendor.jsp](src/main/webapp/add_vendor.jsp) | Create |
| Edit Vendor | [edit_vendor.jsp](src/main/webapp/edit_vendor.jsp) | Update |
| View Vendor | [view_vendor.jsp](src/main/webapp/view_vendor.jsp) | Read-only detail, compliance-document list |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Q1 | Add Vendor | [add_vendor.jsp](src/main/webapp/add_vendor.jsp) form | native POST | `POST /AddVendorServlet` | [AddVendorServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/AddVendorServlet.java:21) | `vendors`, `audit_logs` | vendor name required; phone validated via `PhoneValidationUtil` and rejected outright (not silently dropped) if malformed; duplicate name/email relies on the DB's `UNIQUE KEY` constraints (no pre-check query, caught generically as "possible duplicate") | SUPER_ADMIN/ADMIN/ASSET_MANAGER | Yes — both success and the generic add-failure/possible-duplicate path | **No** — same unescaped-HTML-email gap as Categories/Maintenance/Returns (5th confirmed module) | `?error=invalidphone/failed/server` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | `gst_number` is hardcoded to `NULL` in the INSERT ([VendorDAO.java:79-80](src/main/java/com/mycompany/asset_management_system_ams/VendorDAO.java:79)) and never referenced anywhere else in the module — see Finding 1 |
| Q2 | Edit Vendor | edit_vendor.jsp | native POST | `POST /UpdateVendorServlet` | not fully re-traced this pass | `vendors`, `audit_logs` | — | assetOps | — | — | — | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | `gst_number` confirmed absent from `UpdateVendorServlet`/`VendorDAO` entirely (only the one INSERT reference exists in the whole module, per a full-file grep) — the field is permanently unreachable, not just uncollected at creation |
| Q3 | Delete (Disable) Vendor | vendors.jsp row action | native **POST** | `POST /DeleteVendorServlet` | [DeleteVendorServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/DeleteVendorServlet.java:27) | `vendors`, `category_vendor_mapping`, `audit_logs` | vendorId required | assetOps | Yes | Unescaped (same pattern) | `?error=invalid/deletefailed/server` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **Genuinely well-designed**: `VendorDAO.deleteVendor()` is transactional and correctly cascades — sets `vendors.vendor_status='INACTIVE'` **and** `category_vendor_mapping.status='INACTIVE'` for every mapping involving that vendor in the same transaction ([VendorDAO.java:224-252](src/main/java/com/mycompany/asset_management_system_ams/VendorDAO.java:224)), with its own code comment stating the deliberate design intent: `"Official-safe behavior: do not hard-delete supplier history."` A real soft-delete, done correctly, with the right cascading side-effect handled atomically. Also confirms the GET→POST fix (5th confirmed module) |

### Finding 1 (Medium, compliance-relevant) — `gst_number` is a permanently unreachable field

`vendors.gst_number` exists in the schema ([schema.sql:830](schema.sql:830) per Module 1's original read) but is hardcoded to `NULL` at creation and never referenced by any other method in `VendorDAO` or either of the two vendor-mutating servlets — the same "unreachable through any UI action" pattern found in Module 16's category depreciation defaults, but arguably more consequential here: GST (Goods and Services Tax) registration numbers are a standard compliance/invoicing requirement for vendor management in an Indian public-sector context (this system is built for "East Coast Railway," per the Phase-0 inventory), and a vendor master-data module with no way to ever record one is a real functional gap for procurement/tax-compliance workflows, not merely cosmetic.

---

## 3. Business Workflow / Lifecycle Check

- **Deactivation cascades correctly and safely** to dependent `category_vendor_mapping` rows, directly enforcing the precondition Module 4 already confirmed `AddAssetServlet` depends on (an *active* mapping is required to add an asset under a category+vendor combination) — disabling a vendor here correctly and immediately closes off new asset creation against that vendor everywhere else in the system, in one atomic step. This is good cross-module consistency, achieved deliberately (per the code's own framing) rather than incidentally.
- **No hard delete anywhere** — vendor history (and by extension, any asset that references a since-disabled vendor) is preserved, consistent with the "preserve history" philosophy already seen for Assets, Employees, and Categories.

---

## 4. Data Model Check

`vendors` (per Module 1's original schema excerpt): `vendor_id, vendor_name (UNIQUE), contact_person, email (UNIQUE), phone, address, gst_number, vendor_status (enum), created_at, updated_at`. Finding 1 is the sole notable gap; otherwise a clean, appropriately-constrained table.

---

## 5. Status Model Check

Simple `ACTIVE`/`INACTIVE` toggle, correctly cascaded to dependent mapping rows. No impossible-state risk identified.

---

## 6. RBAC & Security Check

- **CSRF**: app-wide gap; low incremental risk (disable is non-destructive/reversible, matching Module 16's reasoning).
- **RBAC enforcement**: correct, consistent.
- **GET→POST fix**: confirmed applied here too (5th confirmed instance across Categories, Employees, Departments, Maintenance-resolution, and now Vendors).

---

## 7. Audit Log & Data Integrity Check

- Both success and failure paths logged on Add; disable is logged.
- No data-integrity concerns beyond Finding 1.

---

## 8. Missing Features / Gaps

- **Finding 1**: `gst_number` unreachable.
- Unescaped email HTML (cross-cutting, shared with Modules 10/12/16).
- No duplicate-name/email pre-check with a specific error message (relies on the DB constraint + a generic error, same minor UX rough edge as Module 16).

---

## 9. Advanced Feature Recommendations

- **P1** — Add `gst_number` to the Add/Edit Vendor forms and wire it into `VendorDAO`'s INSERT/UPDATE — a real compliance gap worth prioritizing above the cosmetic findings elsewhere in this audit.
- **P1** — Apply `HtmlEscapeUtil.escape()` to this module's email bodies (shared cross-cutting fix).
- **P2** — Surface a specific duplicate-name/email error message.
- **P3** — CSRF tokens (shared app-wide recommendation).

---

## 10. Test Cases

No dedicated test file found for this module in the Phase-0 inventory.

- [ ] **Functional**: creating a vendor with valid data succeeds; duplicate name or email is rejected (via the DB constraint)
- [ ] Invalid phone format is rejected outright, not silently dropped
- [ ] **Regression test for Finding 1**: attempt to set a GST number via the Edit form — confirm it currently has no effect anywhere (documents the gap)
- [ ] Disabling a vendor cascades to `INACTIVE` on all of that vendor's `category_vendor_mapping` rows in the same transaction
- [ ] Attempting to add an asset under a category+now-disabled-vendor combination is blocked (cross-module regression check against Module 4)
- [ ] **RBAC**: EMPLOYEE/AUDITOR/DEPARTMENT_HEAD cannot POST to any of the three servlets
- [ ] Confirm a plain `GET /DeleteVendorServlet?id=N` does not disable the vendor (regression check for the already-fixed vulnerability)
- [ ] **Security**: direct `curl -X POST /AddVendorServlet` with a valid ASSET_MANAGER session and no CSRF-equivalent token succeeds (documents the shared CSRF gap)

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 6 | Core CRUD complete; GST-number gap is a real compliance shortfall |
| Lifecycle support | 8 | Cascading soft-disable is genuinely well-engineered |
| Data integrity | 6 | Finding 1 is a real, unreachable compliance field |
| UX | 7 | Generic duplicate error is a minor rough edge |
| Validation | 7 | Good phone validation; reasonable overall |
| RBAC | 8 | Correct, consistent |
| Security | 6 | Unescaped email HTML; GET→POST fix confirmed applied |
| API integration | 7 | Consistent conventions |
| DB integrity | 7 | Good UNIQUE constraints, correct cascading transaction |
| Auditability | 7 | Adequate logging |
| Reliability | 8 | Transactional cascade handling is a real strength |
| Performance | 8 | Simple, lightweight module |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Covered under Module 24 |

**Overall status: MINOR WORK REQUIRED**

The cascading vendor-disable transaction is genuinely well-built, and this module's disable path is a clean, correctly-scoped soft-delete. The GST-number gap is the one finding here worth elevating above "cosmetic" — for a real Indian public-sector procurement system, the inability to ever record a vendor's tax registration number is a functional, not just data-modeling, shortfall.
