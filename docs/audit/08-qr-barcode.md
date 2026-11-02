# Module 8 Audit — QR/Barcode Tagging & Scanning

**Scope:** QR token generation/reissue/bulk-generate (`GenerateAssetQrServlet`, `BulkGenerateAssetQrServlet`, `ReissueAssetQrTokenServlet`, `RefreshAssetQrUrlsServlet`, `ManageQrUrlsServlet`), the public-URL builder (`QrUrlUtil`), the snapshot-sync mechanism (`QrSnapshotService`), and — the highest-risk surface in this module — the **unauthenticated public scan landing page** (`public_scan_result.jsp` → `public_asset_view.jsp`). This is the largest module by page count (~20 JSPs); this pass concentrates depth on the security-critical generation/public-view/scan-logging path and the tagging-status workflow, and treats the ~10 read-only QR report/analytics JSPs (coverage, exception, IP-audit, scan-analytics, reissue-history reports) as lower-depth this pass, deferred to Module 24 for their export/reporting mechanics specifically.
**Verification layers used:** (a) static code reading — full for the servlets and the public JSP's data-access logic. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory (core flow; full ~20-page list per Phase-0 inventory)

| Page | File | Purpose |
|---|---|---|
| QR Control Center | qr_control_center.jsp | Hub: generate, bulk-generate, tagging status, links to all sub-reports |
| Bulk Generate | qr_bulk_generate.jsp | Batch token generation across many assets |
| Asset QR Card / Print | asset_qr_card.jsp, qr_print.jsp, qr_print_labels.jsp | Printable label views |
| Tagging Status / Work Order | qr_tagging_status.jsp, qr_tagging_work_order.jsp | Physical-tagging progress tracking |
| Token Lookup / Reissue | qr_token_lookup.jsp, qr_token_reissue.jsp, qr_reissue_history.jsp | Look up and reissue a compromised/lost token |
| URL Refresh | qr_url_refresh.jsp | Rebuild public URLs after a base-URL/domain change |
| Scanner (internal, authenticated) | qr_scanner.jsp | Staff-facing camera scan entry point |
| Scan Result (internal) | scan_result.jsp | Authenticated scan landing/detail |
| **Public Scan Result** | **public_scan_result.jsp** | **Unauthenticated** redirect/normalizer for scanned QR payloads |
| **Public Asset View** | **public_asset_view.jsp** | **Unauthenticated** asset detail landing page — the actual public surface |
| QR System Health / Sync Queue | qr_system_health.jsp | Snapshot-sync queue health |
| ~10 QR report/analytics JSPs | qr_coverage_report.jsp, qr_exception_report.jsp, qr_missing_qr_report.jsp, qr_ip_audit_report.jsp, qr_scan_analytics.jsp, qr_scan_logs.jsp, qr_asset_register.jsp, etc. | Reporting layer — deferred to Module 24 |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H1 | Generate/Refresh QR (single asset) | view_asset.jsp / asset_qr_card.jsp → GenerateAssetQrServlet | native POST | `POST /GenerateAssetQrServlet` | [GenerateAssetQrServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/GenerateAssetQrServlet.java:23) | `assets` (qr_public_token/qr_code), `public_asset_snapshot` (sync), `audit_logs` | asset must exist, public base URL must be configured (`QrUrlUtil.isPublicBaseUrlReady()`) before a token is even generated ([GenerateAssetQrServlet.java:57](src/main/java/com/mycompany/asset_management_system_ams/GenerateAssetQrServlet.java:57)) — sensible guard against generating a QR that would point nowhere useful | SUPER_ADMIN/ADMIN/ASSET_MANAGER, checked inline ([GenerateAssetQrServlet.java:37](src/main/java/com/mycompany/asset_management_system_ams/GenerateAssetQrServlet.java:37)), matches `RoleAccessUtil`'s `assetOps` mapping | Yes — `QR_GENERATE` | Not found in this servlet | `?error=invalid_qr_asset/public_base_url/asset_notfound` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Token generated via `java.security.SecureRandom` ([GenerateAssetQrServlet.java:19](src/main/java/com/mycompany/asset_management_system_ams/GenerateAssetQrServlet.java:19)) — correctly unpredictable, consistent with the fix already noted in Module 4 (`AssetDAO.addAsset`'s own token generation). Immediately triggers `QrSnapshotService.syncAssetQuietly()` after the token update ([GenerateAssetQrServlet.java:85](src/main/java/com/mycompany/asset_management_system_ams/GenerateAssetQrServlet.java:85)) — good, proactive sync rather than relying on a batch job |
| H2 | Bulk Generate | qr_bulk_generate.jsp | native POST | `POST /BulkGenerateAssetQrServlet` | not fully read this pass | `assets`, `public_asset_snapshot`, `audit_logs` | — | Same three-role check confirmed by direct grep ([BulkGenerateAssetQrServlet.java:39](src/main/java/com/mycompany/asset_management_system_ams/BulkGenerateAssetQrServlet.java:39)) | Not confirmed | Not confirmed | Not assessed | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | — |
| H3 | Reissue Token | qr_token_reissue.jsp | native POST | `POST /ReissueAssetQrTokenServlet` | not fully read this pass | `assets`, `asset_qr_token_history` (per Module inventory), `audit_logs` | — | Same three-role check confirmed by direct grep ([ReissueAssetQrTokenServlet.java:37](src/main/java/com/mycompany/asset_management_system_ams/ReissueAssetQrTokenServlet.java:37)) | Records `reissued_by_user_id`/`_username`/`_role` in a dedicated history table (schema-confirmed, [schema.sql:178-180](schema.sql:178)) — genuinely good practice for a security-sensitive action (invalidating an old public token) | Not confirmed | Not assessed | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | — |
| H4 | **Public QR scan landing** | (physical tag) → public_scan_result.jsp | native GET, unauthenticated | `GET public_scan_result.jsp?token=/qr=/code=...` | inline JSP → redirects to `public_asset_view.jsp?token=...` | none (pure normalize-and-redirect) | Accepts `token`, `qr`, or `code` param names, and even a raw `...&token=X&...` string pasted as a single value, stripping out the actual token substring ([public_scan_result.jsp:9-31](src/main/webapp/public_scan_result.jsp:9)) | Deliberately public — `RoleAccessUtil.hasAccess()` explicitly allows `public_scan_result.jsp` with no session required ([RoleAccessUtil.java:528](src/main/java/com/mycompany/asset_management_system_ams/RoleAccessUtil.java:528), documented in that file's own comment as a prior fix — this page used to be incorrectly redirected to login) | n/a | n/a | Always redirects, even with an empty token | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | — |
| H5 | **Public Asset View (the actual data page)** | public_asset_view.jsp | native GET, unauthenticated | `GET public_asset_view.jsp?token=...` | inline JSP, two-tier lookup | `public_asset_snapshot` (primary), `assets`/`asset_allocation`/`employees`/`asset_returns`/`maintenance_logs` (fallback), `asset_qr_scan_logs` (every visit logged) | Token-gated only — no other input validation needed for a read-only public page | Deliberately public, matching H4 | Not a mutating action — logs to `asset_qr_scan_logs` instead (see Finding below) | n/a | Renders a "not found"-style state when the token resolves to nothing (`validToken=false`) | Code | **CODE LOOKS CORRECT, BUT see Finding 1 (data-minimization inconsistency)** | **Medium** | **Two-tier data lookup: `getAssetSnapshotByToken()` queries the purpose-built `public_asset_snapshot` table, which deliberately zeroes out `serial_number`, `model_number`, `vendor_name`, and — critically — `holder_name`/`holder_code`/`holder_designation` ([public_asset_view.jsp:177-180](src/main/webapp/public_asset_view.jsp:177), all hardcoded to `''`) before ever reaching the page — a real, deliberate privacy-by-design choice for a page anyone who can physically read a tag can open. But when that snapshot lookup misses (`asset.isEmpty()`), the page falls back to `getAssetByAnyQrValue()`, which queries `assets`/`asset_allocation`/`employees` **directly and live**, and *does* populate `holder_name`/`holder_code`/`holder_designation`/`allocation_date` from the currently-allocated employee's real record ([public_asset_view.jsp:352-368](src/main/webapp/public_asset_view.jsp:352), confirmed rendered at [public_asset_view.jsp:816](src/main/webapp/public_asset_view.jsp:816) area) — to an anonymous visitor. Both lookups are correctly gated on the same secret `qr_public_token` (the fallback's `WHERE` clause only matches `a.qr_public_token = ?`, not a guessable code — confirmed at [public_asset_view.jsp:439-441](src/main/webapp/public_asset_view.jsp:439), so this is not a broken access boundary), but it is an inconsistent one: the same valid physical tag can either redact or reveal which named employee currently holds that asset, depending purely on whether `QrSnapshotService`'s background sync happens to have a current row for it. Since the sync helper is explicitly named `syncAssetQuietly` and swallows its own failures, a sync gap silently switches a scanned tag from the privacy-conscious view to the more revealing one with no visible signal to anyone that this happened.** |

---

## 3. Business Workflow / Lifecycle Check

- **Token lifecycle**: generate → (optional) reissue on suspected compromise/reprint → scan. Reissue correctly maintains a history table rather than just overwriting the token silently (§2/H3) — good auditability for "was this specific physical tag ever invalidated, and when."
- **Tagging status workflow** (`qr_tagging_status.jsp`/`UpdateQrTaggingStatusServlet`, not fully read this pass) tracks the *physical* act of applying a printed tag to an asset, separate from the *digital* token's existence — a sensible two-track model (a token can exist digitally before the physical label is ever printed/applied) but not deep-audited this pass.
- **Snapshot sync as a cross-cutting dependency**: `QrSnapshotService.syncAssetQuietly()` is called from at least Module 4 (`UpdateAssetServlet`), Module 5 (`AddAllocationServlet`), and this module's own generation/reissue servlets — meaning the public view's data freshness depends on every one of those call sites remembering to trigger it and it not silently failing. This is a reasonable design (push-based sync on the events that matter, rather than a slow poll) but has no visible fallback alerting if a sync silently fails (consistent with the "quietly" naming) — `qr_system_health.jsp` and `qr_sync_queue` (per the Phase-0 inventory) suggest there IS a monitoring surface for this, which is good, but it wasn't traced in this pass to confirm it would actually surface a specific asset's stale/missing snapshot row in a way that explains Finding 1's fallback trigger condition to an operator.

---

## 4. Data Model Check

- `public_asset_snapshot` (per Module inventory, not re-read here in full): a purpose-built, deliberately-redacted read model for the public page — a genuinely good architectural pattern (don't expose your live operational tables to an anonymous surface, expose a curated copy instead). Its existence and redaction of holder identity fields is direct evidence this was a deliberate privacy decision, which makes the fallback path's contradiction of that decision (Finding 1) more notable, not less — the safer design exists and is bypassed only in a failure/gap scenario, not absent entirely.
- `asset_qr_scan_logs` ([schema.sql, referenced in Module inventory]): `scan_id, asset_id, qr_public_token, scanned_by_user_id, scanned_by_employee_id, scan_source (enum incl. PUBLIC_SCAN), scan_ip, scan_user_agent, scan_status (enum SUCCESS/FAILED/INVALID_TOKEN), remarks, scanned_at` — good schema for distinguishing a public anonymous scan from an authenticated internal one, and for capturing failed/invalid-token attempts (useful for detecting token-guessing/enumeration attempts against the public endpoint, though see §6 on IP-header trust).
- `asset_qr_token_history`: reissue trail with named actor fields, confirmed via `ReissueAssetQrTokenServlet` grep — good design.

---

## 5. Status Model Check

Not a status-machine-heavy module — tokens are either present or not, tagging status is tracked separately (not deep-audited this pass). No impossible-state concerns identified in the portion read.

---

## 6. RBAC & Security Check

- **The public surface is deliberately and correctly unauthenticated** — this is by design, confirmed via `RoleAccessUtil`'s own code comment describing a prior fix where this exact page was mistakenly being redirected to login before the fix, breaking the entire point of a public QR landing page. Good that this was caught and fixed.
- **Finding 1 (Medium, restated from §2/H5)**: the fallback data path's inconsistent exposure of employee holder identity is this module's primary security-relevant finding — not a broken access boundary (the token requirement is intact and unguessable in both paths) but a data-minimization inconsistency that undermines the snapshot table's own evident purpose.
- **IP/User-Agent trust**: `public_asset_view.jsp`'s `clientIp()` helper trusts `X-Forwarded-For`/`X-Real-IP` headers unconditionally with no validation that the request actually came through a trusted proxy that sets them ([public_asset_view.jsp:50-64](src/main/webapp/public_asset_view.jsp:50)) — consistent with the app's general pattern (seen also in `RequestUtil.getClientIpAddress` used elsewhere) rather than unique to this page, but worth flagging here specifically because this is the one page in the entire application reachable by a fully anonymous, untrusted visitor: anyone scanning a public tag can trivially spoof the `scan_ip` value recorded in `asset_qr_scan_logs` by setting an `X-Forwarded-For` header on their request, undermining the forensic value of that log for exactly the audience (an anonymous public visitor) it would matter most for.
- **Token generation** is cryptographically sound (`SecureRandom`) across both the asset-creation path (Module 4) and this module's own generate/reissue servlets — no predictable-token regression found in the parts read.
- **RBAC for privileged QR actions**: consistent SUPER_ADMIN/ADMIN/ASSET_MANAGER gating across generate/bulk-generate/reissue, matching the central `RoleAccessUtil` map.

---

## 7. Audit Log & Data Integrity Check

- Token generate/reissue actions are audit-logged via the standard `AuditDAO`/`audit_logs` path.
- Public scans are logged to a *separate*, purpose-built table (`asset_qr_scan_logs`) rather than the general `audit_logs` — a sensible separation (scan volume from an anonymous public page could be much higher-frequency and lower-signal than genuine administrative actions, and mixing them would dilute `audit_logs.jsp`'s usefulness, consistent with Module 3's finding that page already struggles with a fixed 500-row window).
- Both `SUCCESS` and `INVALID_TOKEN` outcomes are logged ([public_asset_view.jsp:699,701](src/main/webapp/public_asset_view.jsp:699)) — good coverage for detecting scanning/enumeration abuse, undermined somewhat by the unvalidated IP-header trust noted in §6.

---

## 8. Missing Features / Gaps

- **Finding 1**: inconsistent PII exposure between the snapshot and fallback data paths on the public page.
- **IP spoofability** on the one truly public-facing page in the app, weakening the forensic value of its own dedicated scan-log table.
- No visible rate-limiting on `public_asset_view.jsp` itself (Module 1's login lockout mechanism doesn't apply here) — nothing observed in this pass stops rapid automated scanning/enumeration attempts against the public endpoint (mitigated somewhat by the token being unguessable, but repeated invalid-token probing isn't throttled either, unlike login's brute-force lockout).
- Not confirmed this pass whether `qr_system_health.jsp` actually surfaces *which* specific assets have a stale/missing snapshot row (the concrete trigger condition for Finding 1) — if it doesn't, an operator has no way to proactively find and fix the gap before a public scan hits it.

---

## 9. Advanced Feature Recommendations

- **P0** — Resolve Finding 1: either (a) make `getAssetByAnyQrValue()`'s fallback redact holder identity fields the same way the snapshot path does, accepting slightly staler-but-consistent data exposure, or (b) treat a snapshot-miss as a hard "please try again shortly" state rather than silently falling through to a more-revealing live query — either restores the deliberate privacy design's actual guarantee.
- **P1** — Add basic rate-limiting/throttling to `public_asset_view.jsp` for repeated invalid-token attempts from the same source, mirroring the login lockout pattern from Module 1.
- **P1** — Don't trust `X-Forwarded-For`/`X-Real-IP` on the public page without validating the immediate peer is a configured trusted proxy (or document that the deployment's reverse proxy strips/overwrites these headers before they reach the app — not confirmed either way in this pass).
- **P2** — Surface stale/missing snapshot rows proactively on `qr_system_health.jsp` if not already present, so Finding 1's trigger condition is operationally visible and fixable before it's hit by a real scan.
- **P3** — Consider signing or short-expiring the public token if the threat model requires defending against a lost/stolen physical asset being scanned by a finder indefinitely (currently, per this pass, tokens appear to be long-lived until manually reissued).

---

## 10. Test Cases

- [ ] **Functional**: generating a QR for an asset with no configured public base URL is blocked with a clear error, not a broken/non-resolving link
- [ ] A freshly-generated token immediately resolves on `public_asset_view.jsp` (confirms the proactive sync, not just eventual consistency)
- [ ] **Regression test for Finding 1**: construct a scenario where `public_asset_snapshot` has no row for a valid `qr_public_token` (e.g. delete the snapshot row directly) and confirm the resulting public page **currently does** show the allocated employee's name (expected to currently reproduce the finding) — then, post-fix, confirm it does not
- [ ] Invalid/garbage token on `public_asset_view.jsp` renders a clean "not found" state, not a stack trace, and logs `INVALID_TOKEN`
- [ ] **Security**: repeated rapid requests with random invalid tokens against `public_asset_view.jsp` — confirm whether any throttling exists (expected to currently show none)
- [ ] Spoof `X-Forwarded-For` on a public scan request and confirm the spoofed value is what lands in `asset_qr_scan_logs.scan_ip` (documents the IP-trust gap)
- [ ] **RBAC**: EMPLOYEE/AUDITOR cannot POST to `GenerateAssetQrServlet`/`BulkGenerateAssetQrServlet`/`ReissueAssetQrTokenServlet`
- [ ] Reissuing a token correctly invalidates the old one — a scan using the old token after reissue must fail/log as invalid, not succeed
- [ ] **DB integrity**: `assets.qr_public_token` uniqueness constraint holds even under concurrent bulk-generate requests

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 7 | Core generate/reissue/scan flow is solid; report/analytics sub-pages not deep-audited this pass |
| Lifecycle support | 7 | Token generate→reissue history is well modeled |
| Data integrity | 6 | Snapshot table is a strong pattern undermined by an inconsistent fallback (Finding 1) |
| UX | 7 | Clean public-facing page with a sensible not-found state |
| Validation | 7 | Token-gating is sound in both lookup paths |
| RBAC | 8 | Consistent, correct, deliberately-and-correctly public where intended |
| Security | 6 | No token-guessing vector found (strong point), but Finding 1 and IP-spoofability are real, and no rate-limiting on the public endpoint |
| API integration | 7 | Consistent conventions |
| DB integrity | 7 | Good separation of public-read-model vs. operational tables; dependent on a "quiet" sync succeeding |
| Auditability | 7 | Dedicated, appropriately-separated scan-log table with good outcome coverage |
| Reliability | 6 | "Quietly" swallowed sync failures are the direct cause of Finding 1's exposure window |
| Performance | 6 | The fallback query's extensive per-column/per-table `information_schema` existence checks (`tableExists`/`columnExists` called dozens of times per request) are a real per-request overhead on a potentially high-traffic anonymous public page — not measured this pass but worth a runtime performance check under load |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | Not assessed | Deferred to Module 24 |

**Overall status: MINOR WORK REQUIRED**

The architecture here (separate public read-model, cryptographically sound tokens, dedicated scan-log table with a distinct security posture from the internal `audit_logs`) reflects real security-conscious design. The one substantive finding — an inconsistent PII-exposure fallback that only activates on a silent sync failure — is a meaningful but bounded gap, not a broken access boundary. The unaudited report/analytics sub-pages (~10 JSPs) remain a scope caveat on this module's overall score; a follow-up pass focused specifically on those export endpoints (alongside Module 24) would round out full coverage.
