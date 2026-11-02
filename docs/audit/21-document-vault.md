# Module 21 Audit — Document Vault (Cross-Cutting File Upload/Download)

**Scope:** File upload/download across Assets, Employees, and Vendors — `AssetDocumentUploadUtil`/`UploadAssetDocumentServlet`/`DownloadAssetDocumentServlet` (read in full), `UploadEmployeeProfileImageServlet` (read in full), and `EmployeeDocumentUploadUtil`/`VendorDocumentUploadUtil`/their matching servlets (not independently re-read — assessed as following the same pattern family based on the two fully-read implementations, flagged where this is an inference rather than a direct read).
**Verification layers used:** (a) static code reading — full for the two implementations read; representative sampling for the rest, given three near-identical upload/download families exist across Assets/Employees/Vendors. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

File upload/download is embedded within Asset, Employee, and Vendor pages (Modules 4, 9, 17) rather than having dedicated pages of its own — this module audits the shared mechanism, not a standalone UI surface.

| Component | File | Purpose |
|---|---|---|
| Asset document upload | [AssetDocumentUploadUtil.java](src/main/java/com/mycompany/asset_management_system_ams/AssetDocumentUploadUtil.java), [UploadAssetDocumentServlet.java](src/main/java/com/mycompany/asset_management_system_ams/UploadAssetDocumentServlet.java) | Attach supporting documents to an asset record |
| Asset document download | [DownloadAssetDocumentServlet.java](src/main/java/com/mycompany/asset_management_system_ams/DownloadAssetDocumentServlet.java) | Retrieve a previously-uploaded asset document |
| Employee document upload/download | `EmployeeDocumentUploadUtil.java`, `UploadEmployeeDocumentServlet.java`, `DownloadEmployeeDocumentServlet.java`, `DeleteEmployeeDocumentServlet.java` | Employee compliance documents |
| Employee profile image | [UploadEmployeeProfileImageServlet.java](src/main/java/com/mycompany/asset_management_system_ams/UploadEmployeeProfileImageServlet.java) | Profile photo, self- or admin-uploadable |
| Vendor document upload/download | `VendorDocumentUploadUtil.java`, `UploadVendorDocumentServlet.java`, `DownloadVendorDocumentServlet.java` | Vendor compliance documents |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| U1 | Upload Asset Document | view_asset.jsp / add_asset.jsp forms | native POST (multipart) | `POST /UploadAssetDocumentServlet` (also embedded in `AddAssetServlet`, Module 4) | [AssetDocumentUploadUtil.saveAssetDocument](src/main/java/com/mycompany/asset_management_system_ams/AssetDocumentUploadUtil.java:59) | filesystem + `asset_documents` | **Best-in-class file-upload security in this codebase**: extension **whitelist** (`pdf/jpg/jpeg/png/webp/doc/docx/xls/xlsx/csv`), 10MB size cap, MIME type **derived server-side from the validated extension rather than trusted from the client's multipart `Content-Type` header** (explicitly and correctly reasoned in the code's own comment as the actual security control, with the forced-download `Content-Disposition` on the read side framed as a secondary mitigation, not the primary one), a fully randomized stored filename (`type-timestamp-uuid.ext`, original filename preserved only as display metadata in the DB, never used as a storage path segment), and **two independent path-traversal checks** — `Paths.get(submittedName).getFileName()` strips any directory component from the submitted filename, and both the asset-subfolder path and the final target-file path are independently `.normalize()`d and verified with `.startsWith(root)` before any filesystem operation | `RoleAccessUtil` maps `/UploadAssetDocumentServlet` → `assetOps` (SUPER_ADMIN/ADMIN/ASSET_MANAGER) — Module 2's inventory confirms this entry was itself a documented prior fix (the feature was completely broken for every role except SUPER_ADMIN before the `ROLE_MAP` entry was added) | Presumed yes, consistent with `AddAssetServlet`'s embedded upload path (Module 4) which does log `DOCUMENT_UPLOAD` | Not applicable to upload itself | Not fully re-traced for the standalone servlet (only the embedded-in-Add-Asset path was read in Module 4) | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | This is genuinely exemplary, textbook-correct secure file handling — see §6 for full analysis |
| U2 | Download Asset Document | view_asset.jsp document list | native GET | `GET /DownloadAssetDocumentServlet?id=N` | [DownloadAssetDocumentServlet.doGet](src/main/java/com/mycompany/asset_management_system_ams/DownloadAssetDocumentServlet.java:17) | filesystem + `asset_documents` (read) | documentId required, file existence re-checked before serving | SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR/DEPARTMENT_HEAD — matches `verificationViewOps`, Module 2's inventory confirms this too was a documented prior fix (previously broken for everyone but SUPER_ADMIN) | Not applicable (read action) | n/a | Redirects to `view_asset.jsp?...&error=document_missing` on any failure, including a missing file on disk (doesn't crash on a dangling DB reference) | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Correctly forces `Content-Disposition: attachment` (prevents inline rendering of any uploaded content in the browser, a real defense-in-depth measure against stored content being executed even if a malicious file somehow passed upload validation), serves the DB-stored (server-derived, not client-supplied) MIME type, and sanitizes the downloaded filename (`\`, `/`, `"` stripped) before placing it in the `Content-Disposition` header — prevents a malicious original filename from injecting extra header directives. No ownership/ department scoping needed or present, consistent with assets being organization-wide operational data (Module 4's established data-classification) |
| U3 | Upload Employee Profile Image | view_employee.jsp / employee_profile.jsp | native POST (multipart) | `POST /UploadEmployeeProfileImageServlet` | [UploadEmployeeProfileImageServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/UploadEmployeeProfileImageServlet.java:25) | filesystem + `employees.profile_image_path` (or similar) | Content-Type header whitelist (`image/jpeg`/`png`/`webp`) **and** extension whitelist (double-checked, not either/or), 5MB cap, fully server-generated filename (`emp_<id>_<uuid>.<ext>` — no user input in the path at all, safe by construction rather than by traversal-checking) | **Genuine, correctly-scoped three-tier RBAC**: SUPER_ADMIN/ADMIN unconditional; DEPARTMENT_HEAD re-verified server-side via `isEmployeeUnderDepartmentHead()`; **EMPLOYEE can upload their own photo only**, with `targetEmployeeId` cross-checked against the session's own resolved `employeeId` (`employeeDAO.getEmployeeIdByUserId(loggedInUserId) == targetEmployeeId`) — a real, structural IDOR defense, not a policy-only one ([UploadEmployeeProfileImageServlet.java:65-78](src/main/java/com/mycompany/asset_management_system_ams/UploadEmployeeProfileImageServlet.java:65)) | Not confirmed this pass | Not confirmed | `?error=invalid_employee/notfound/unauthorized/missing_file/invalid_type/db_error/upload_failed` | Code | **CODE LOOKS CORRECT, BUT see Finding 1** | Low-Medium | **Weaker than U1 specifically on content-type trust**: this validator whitelists the *client-supplied* `Content-Type` header and the file extension, but — unlike `AssetDocumentUploadUtil`, which explicitly avoids trusting the client header at all by deriving the served MIME type from the validated extension — neither check here inspects the file's actual byte content (no magic-number/signature verification). A file with a spoofed `Content-Type: image/png` header and a `.png` extension, but whose actual bytes are something else entirely (e.g. a polyglot file valid as both an image and an HTML/SVG-with-script payload), would pass both checks.** |

---

## 3. Business Workflow / Lifecycle Check

- **Upload validation quality varies meaningfully across the two implementations read**, and this variance is itself worth documenting for the final report: `AssetDocumentUploadUtil` (U1) represents the codebase's strongest security thinking on file handling, explicitly reasoning about and correctly avoiding the classic "trust the client's Content-Type header" mistake; `UploadEmployeeProfileImageServlet` (U3) is still reasonably good (whitelist-based, size-capped, safe-by-construction filenames) but reverts to trusting the client header as one of its two checks, a step down in rigor. Given `EmployeeDocumentUploadUtil`/`VendorDocumentUploadUtil` were not independently read this pass, it's unconfirmed which pattern each actually follows — flagged as a direct follow-up.
- **Deletion**: `AssetDocumentUploadUtil.deleteIfManaged()` is deliberately "best effort" — a locked/in-use file on disk doesn't block the corresponding database cleanup ([AssetDocumentUploadUtil.java:152-159](src/main/java/com/mycompany/asset_management_system_ams/AssetDocumentUploadUtil.java:152)) — a pragmatic choice consistent with Module 4's observed pattern of cleaning up orphaned uploads on a later validation failure.
- **Access control model is consistent with each parent module's own data-classification**: Assets (organization-wide, Module 4) get broad read access with no ownership scoping; Employees (has genuine self-service/privacy dimensions, Module 9) get real per-employee ownership checks for the one self-service action found (U3). This is the correct differentiation, not an inconsistency.

---

## 4. Data Model Check

`asset_documents` (Module 4's inventory), `employee_documents` (Module 9's schema excerpt: `document_id, employee_id, document_title, document_type, original_file_name, stored_file_name, stored_file_path, mime_type, file_size, uploaded_by, uploaded_at, status`) — both tables correctly separate the original (display-only) filename from the stored (server-controlled, randomized) filename and path, which is exactly the right schema shape to support the path-safety guarantees enforced in code. `document_vault` (a fourth, more general-purpose table seen in the schema, [schema.sql:412-416](schema.sql:412), with `ref_type`/`ref_id` covering ASSET/EMPLOYEE/VENDOR/MAINTENANCE/DISPOSAL/RETURN/VERIFICATION/REQUEST) exists but wasn't confirmed as actually used by any of the servlets read this pass — possibly a more generic/newer document-attachment mechanism than the three per-entity tables actually wired up, worth a follow-up to confirm whether it's live, planned, or superseded.

---

## 5. Status Model Check

Not a status-machine module; `employee_documents.status` (varchar, default `ACTIVE`) suggests a soft-delete-style status for documents, consistent with the codebase's general "preserve history" philosophy, though not independently confirmed this pass whether `DeleteEmployeeDocumentServlet` does a soft status flip or a hard delete.

---

## 6. RBAC & Security Check

- **U1/U2 (Asset Documents) represent the strongest, most carefully-reasoned file-handling security in the entire codebase** — worth highlighting prominently in the final report as a positive example, not just absence of findings. The path-traversal defense specifically (double normalize+startsWith checks, on both write and read paths, plus filename-component stripping on the submitted name) is textbook-correct and defends against the classic `../../../` and null-byte-style traversal attempts.
- **Finding 1 (Low-Medium)**: U3's reliance on a client-supplied `Content-Type` header as one of its two validation checks is a real, if modest, gap relative to U1's stronger standard — worth aligning to the same "derive, don't trust" approach, especially since profile images are a comparatively softer target (limited blast radius — displayed as an `<img>`, not served as a general download) but still worth hardening for consistency.
- **CSRF**: app-wide gap applies to all upload actions.
- **IDOR**: U1/U2 appropriately have none (by design, per data classification); U3 has genuine, correct, structural protection.
- **RBAC gaps found and fixed elsewhere**: both U1 and U2's `RoleAccessUtil` entries are explicitly documented (in Module 2's inventory) as having been *completely broken* (403 for every role but SUPER_ADMIN) before being fixed — this module's read/write access was previously non-functional for its actual intended audience, now corrected.

---

## 7. Audit Log & Data Integrity Check

- Asset document upload (embedded in `AddAssetServlet`, per Module 4) is audit-logged; the standalone `UploadAssetDocumentServlet`'s own logging wasn't independently re-confirmed this pass.
- No integrity concerns found in the parts read — the schema/code split between display-name and storage-name/path is correctly and consistently maintained.

---

## 8. Missing Features / Gaps

- **Finding 1**: U3's weaker content-type trust model relative to U1.
- `EmployeeDocumentUploadUtil`/`VendorDocumentUploadUtil` not independently confirmed to match U1's stronger standard — flagged as an open item, not a confirmed gap.
- The apparently-unused `document_vault` generic table's actual status (live/planned/superseded) is unconfirmed.
- No magic-byte/content-sniffing validation anywhere in this module (even U1, despite its otherwise excellent design, validates by extension/derived-type rather than by inspecting actual file content) — a defense-in-depth gap common to almost all upload validators of this style, not unique to this codebase, but worth noting as a further-hardening opportunity given how much care was clearly already invested here.

---

## 9. Advanced Feature Recommendations

- **P1** — Align `UploadEmployeeProfileImageServlet` (and confirm/align `EmployeeDocumentUploadUtil`/`VendorDocumentUploadUtil`) to `AssetDocumentUploadUtil`'s stronger pattern: derive the served content type from the validated extension rather than trusting the client header.
- **P1** — Confirm whether `EmployeeDocumentUploadUtil`/`VendorDocumentUploadUtil` implement the same path-traversal double-check as `AssetDocumentUploadUtil` — this is the single most important thing to verify in a follow-up pass, since a weaker implementation in either would be a genuine path-traversal risk, not just a style inconsistency.
- **P2** — Add basic magic-byte/signature verification (e.g. confirm a `.pdf` upload actually starts with `%PDF-`) as defense-in-depth beyond extension/header checks, across all upload paths.
- **P3** — Confirm and document the `document_vault` table's actual role, or remove it if superseded.
- **P3** — CSRF tokens (shared app-wide recommendation).

---

## 10. Test Cases

No dedicated test file found for this module's file-handling logic specifically.

- [ ] **Functional**: uploading an allowed file type within the size limit succeeds and is downloadable, with the original filename preserved for display and the served content type matching the actual file type
- [ ] **Security — path traversal**: attempt to upload a file with a submitted filename containing `../../../etc/passwd`-style path segments — assert the stored path stays within the managed upload root (regression-critical for U1's core defense)
- [ ] Attempt to request a download with a `stored_file_path` value (if ever reachable via a crafted `document_id`/DB manipulation) pointing outside the upload root — assert `resolveManagedPath()` rejects it
- [ ] **Security — content-type spoofing**: upload a file with a `.pdf` extension whose actual content is HTML/script, with a manually-set `Content-Type: application/pdf` — assert U1 serves it back with the *derived* (not client-supplied) content type; repeat for U3 and assert whether the same protection holds (expected to currently show a gap per Finding 1)
- [ ] **Negative/Boundary**: oversized file rejected; disallowed extension rejected; empty file rejected
- [ ] **RBAC**: EMPLOYEE cannot upload an asset document; EMPLOYEE can upload their own profile image but not another employee's (structural IDOR check, not just a policy check)
- [ ] Confirm the previously-broken `RoleAccessUtil` entries for asset document upload/download (per Module 2's inventory) remain fixed — regression guard
- [ ] **DB integrity**: deleting a document record removes the corresponding file (or fails gracefully/best-effort if locked, per the documented design)

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 8 | Core upload/download/delete flow complete across all three entity types (Assets fully confirmed, Employees/Vendors partially inferred) |
| Lifecycle support | 8 | Consistent "preserve history, best-effort file cleanup" philosophy |
| Data integrity | 8 | Clean schema separation of display vs. storage identifiers |
| UX | 8 | Clear error codes, graceful handling of a missing file on disk |
| Validation | 8 | U1 is excellent; U3 is good but a step down; unconfirmed for the rest |
| RBAC | 8 | Correct, including genuine structural self-service IDOR protection (U3) and documented prior fixes for previously-broken access (U1/U2) |
| Security | 8 | U1's path-traversal and content-type handling is genuinely the strongest in this codebase; Finding 1 is a real but modest gap in one sibling implementation |
| API integration | 7 | Consistent conventions |
| DB integrity | 7 | Clean; the `document_vault` table's status is an open question |
| Auditability | 6 | Confirmed for the Asset-creation-embedded path; not independently confirmed for standalone upload/download servlets |
| Reliability | 8 | Graceful handling of missing files, locked-file deletion |
| Performance | 7 | No inefficiencies observed |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Not applicable to this module |

**Overall status: MINOR WORK REQUIRED**

The Asset Document upload/download implementation (U1/U2) is genuinely exemplary file-handling security — the strongest, most carefully-reasoned code of its kind found anywhere in this audit, and worth highlighting as a model for the rest of the codebase rather than merely passing review. The one confirmed gap (Finding 1, weaker content-type trust in the profile-image path) and the open question about whether the Employee/Vendor document siblings match U1's standard are both worth closing, but neither undermines the module's overall strong foundation.
