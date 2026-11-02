# Module 24 Audit — Reports & Exports

**Scope:** `reports.jsp`/`analytics.jsp` (on-screen reporting) and the 23 `export_*.jsp` Excel-export endpoints spanning nearly every other module (Assets, Audit Logs, Categories, Category-Vendor Mapping, Departments, Disposal, Employees, Maintenance, QR — 11 of the 23, Requests, Returns, Warranty). Given the count, this pass reads one export end-to-end (`export_asset_report.jsp`, unfiltered/no-parameter) and one filtered/parameterized export in full (`export_qr_asset_scan_history_excel.jsp`) as representative deep samples, plus a role-gate and parameter-usage sweep across all 23 files; findings below are reported with the confidence level appropriate to how each was verified.
**Verification layers used:** (a) static code reading — full for the two sampled files, sweep-level for the rest. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Reports | [reports.jsp](src/main/webapp/reports.jsp) | On-screen report hub |
| Analytics | [analytics.jsp](src/main/webapp/analytics.jsp) | On-screen analytics/KPI views |
| 23 Export endpoints | `export_*.jsp` | Excel (`.xlsx`, via Apache POI) exports, one per module/report — full inventory in the Phase-0 module list |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| X1 | Export Asset Report (representative: unfiltered, full-dump style export) | assets.jsp → export link | native GET | `GET /export_asset_report.jsp` | inline JSP | `assets` + joined lookups (read) | None needed — no filter parameters accepted, full unfiltered export | SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR ([export_asset_report.jsp:242-244](src/main/webapp/export_asset_report.jsp:242)), matches `reportExportOps` | Not confirmed this pass whether export actions themselves are audit-logged (a real gap if not — Module 3 flagged this exact open question for the audit-log export specifically) | n/a | Not assessed | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Correctly parameterized (`PreparedStatement`, no dynamic WHERE, no injection surface since there's nothing user-supplied to inject) — good, simple, safe |
| X2 | Export QR Asset Scan History (representative: filtered/parameterized export) | qr_asset_scan_history.jsp → export link | native GET | `GET /export_qr_asset_scan_history_excel.jsp?q=...&status=...` | inline JSP | `asset_qr_scan_logs` + joined lookups (read) | search term (`q`) and status filter accepted from the query string | SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR (`qrViewOps`) | Not confirmed | n/a | Not assessed | Code | **CODE LOOKS CORRECT, BUT see Finding 1** | Low | **The `q` search parameter is correctly bound via `PreparedStatement`/`setString()` for the actual SQL `WHERE ... LIKE ?` clause ([export_qr_asset_scan_history_excel.jsp:241-287](src/main/webapp/export_qr_asset_scan_history_excel.jsp:241)) — no SQL injection risk. However, the same raw `q` value is also written directly into a visible Excel cell as report metadata ("Search: " + q, [export_qr_asset_scan_history_excel.jsp:212](src/main/webapp/export_qr_asset_scan_history_excel.jsp:212)) with no sanitization against a leading `=`, `+`, `-`, or `@` character — the classic **CSV/Excel formula-injection** pattern. If a search term starting with one of those characters is ever entered (by an operator, or reflected from any upstream source that isn't itself sanitized) and the resulting file is later opened in Excel by a user with formula auto-execution behavior, that cell could be interpreted as a formula rather than plain text.** |

Given the sweep found `request.getParameter` usage in 6 of the 23 export files (all QR-report exports: scan history, exception report, IP audit, missing-QR, reissue history, tagging status — per the file-level grep), **Finding 1's pattern should be treated as applying to all 6**, not just the one fully read, pending direct confirmation of each — the shared code style (same header-building helper functions, same file-naming convention) strongly suggests they're generated from a common template/pattern rather than independently written, making a shared fix (and a shared vulnerability, until fixed) the more likely reality than an isolated instance.

---

## 3. Business Workflow / Lifecycle Check

Not a lifecycle-bearing module — these are read-only reporting/export endpoints layered on top of the lifecycle state every other module already manages and audits independently.

---

## 4. Data Model Check

Not applicable — no dedicated tables; reads across the schema.

---

## 5. Status Model Check

Not applicable.

---

## 6. RBAC & Security Check

- **RBAC role-gate presence confirmed across all 23 export files** (each has its own inline role check, per the sweep) — consistency of *presence* is good; consistency of the *exact role list per report* was not individually re-verified for all 23 beyond the two sampled and the several already cross-referenced from earlier modules (Module 2/3's inventory notes on `export_audit_logs.jsp` being deliberately narrower than most, `export_qr_*` matching `qrViewOps`, etc.) — no drift found in what was checked.
- **Finding 1 (Low)**: formula-injection risk on reflected search terms in at least one, likely up to six, export files. Low severity because: (a) the search term is supplied by an already-authenticated, already-privileged user (SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR), not an anonymous attacker; (b) it would require that same privileged user (or someone who can influence what they search for) to intentionally craft a payload and then have another privileged user open the resulting file in a formula-auto-executing context — a real but narrow chain, not a direct external attack surface. Still worth fixing given how mechanical the fix is (prefix a defensive character like `'` or strip/escape leading formula-trigger characters before writing to the cell).
- **No SQL injection risk found** in either sampled file, nor any red flags in the broader sweep (all filter usage observed goes through the `PreparedStatement`/`?`-placeholder pattern).
- **CSRF**: not applicable — all export actions are GET/read-only.

---

## 7. Audit Log & Data Integrity Check

- **Open question, not confirmed either way this pass**: whether any export action itself writes an audit-log entry (e.g., "user X exported the Asset Report at time Y"). Module 3 specifically flagged this exact question for `export_audit_logs.jsp` (a meta-concern: exporting the audit trail should itself probably be audited) and it applies equally to all 23 export endpoints here — for compliance purposes, knowing *who downloaded what report and when* can matter as much as the report's own contents, especially for anything touching financial (purchase cost, disposal value) or personal (employee) data. This should be directly confirmed in a follow-up pass rather than assumed either way.

---

## 8. Missing Features / Gaps

- **Finding 1**: formula-injection risk in reflected search terms (confirmed in one file, likely present in up to five more).
- **Export actions are not confirmed to be audit-logged** — a real gap if true, given several of these reports contain financial and personal data.
- No dry-run/preview before a large export — not itself a defect, just noted as a UX absence.

---

## 9. Advanced Feature Recommendations

- **P1** — Sanitize any user-supplied text reflected into an Excel cell across all export endpoints (prefix with `'` or strip a leading `=`/`+`/`-`/`@`) — a small, mechanical, high-value fix given how many files likely share the pattern.
- **P1** — Confirm whether exports are audit-logged; if not, add a lightweight `EXPORT` audit entry (module name + acting user) to each of the 23 endpoints, consistent with how thoroughly this codebase audits mutating actions elsewhere.
- **P2** — Standardize the QR-report export family's shared header/filter-building logic into a common utility if not already done, so Finding 1's fix (and any future fix) only needs to be made once rather than six times.
- **P3** — Consider streaming very large exports rather than building the entire workbook in memory, if any report's underlying table could grow large enough for this to matter (not confirmed as a current problem, a forward-looking note).

---

## 10. Test Cases

No dedicated test file found for this module in the Phase-0 inventory.

- [ ] **Functional**: each of the 23 export endpoints produces a valid, openable `.xlsx` file with the expected columns
- [ ] **Regression test for Finding 1**: submit a search term starting with `=`, `+`, `-`, or `@` (e.g. `=1+1` or `=HYPERLINK("http://example.com","click")`) to `export_qr_asset_scan_history_excel.jsp` (and the other 5 QR-export files with a `q` parameter) — open the resulting file and confirm the cell is **not** interpreted as a live formula (expected to currently **fail** for at least the one confirmed file)
- [ ] **RBAC**: for each export, confirm a role outside its documented allowed list receives a 403/redirect, not the file
- [ ] **Security**: confirm the `q`/filter parameters cannot be used for SQL injection despite being reflected in the file (should currently **pass** — the binding is correct, only the cell-reflection is the gap)
- [ ] **Audit**: confirm (or refute) whether any export writes an `audit_logs` entry — resolves the open question in §7
- [ ] **Performance**: export the largest realistic dataset for at least one report (e.g. `audit_logs` or `asset_qr_scan_logs`, both likely to grow largest over time) and confirm acceptable response time/memory usage

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 8 | Broad, consistent coverage across nearly every module |
| Lifecycle support | N/A | Not applicable |
| Data integrity | 7 | Accurate reflection of underlying data; the one open concern is Finding 1 |
| UX | 7 | Consistent, professional report formatting (title/subtitle/KPI rows, per the sampled files) |
| Validation | 7 | Good parameter handling for the SQL layer; the cell-reflection gap is a separate, narrower issue |
| RBAC | 8 | Consistently present and role-gated across all 23 endpoints |
| Security | 6 | No SQL injection found; formula-injection is a real, if narrow-impact, gap likely spanning multiple files |
| API integration | 7 | Consistent conventions |
| DB integrity | N/A | Read-only module |
| Auditability | 5 | Unconfirmed whether export actions themselves are logged — a real gap if not, given the financial/personal data several reports contain |
| Reliability | 7 | No inefficiencies observed in the sampled files |
| Performance | Not assessed | Large-dataset behavior not tested this pass |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | 8 | This module's entire purpose, executed competently |

**Overall status: MINOR WORK REQUIRED**

A broad, consistently-built reporting layer with correct SQL parameterization throughout. The formula-injection finding is mechanical to fix and low-severity given the privileged-user-only threat model; the unconfirmed export-audit-logging question is the more consequential open item, worth resolving directly rather than left assumed, given how many of these 23 reports touch financial or personal data that a real organization would want a "who exported this and when" trail for.
