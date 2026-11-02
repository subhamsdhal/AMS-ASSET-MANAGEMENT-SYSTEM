# Module 13 Audit — Disposal / Retirement

**Scope:** Asset disposal (`DisposeAssetServlet`, `AssetDAO.disposeAsset`), the only servlet touching this workflow.
**Verification layers used:** (a) static code reading — full. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Dispose Asset | [dispose_asset.jsp](src/main/webapp/dispose_asset.jsp) | Disposal form: date, reason, value, remarks |
| View Disposal | [view_disposal.jsp](src/main/webapp/view_disposal.jsp) | Read-only disposal record detail |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| M1 | Dispose Asset | [dispose_asset.jsp](src/main/webapp/dispose_asset.jsp) form | native POST | `POST /DisposeAssetServlet` | [DisposeAssetServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/DisposeAssetServlet.java:30) | `asset_disposal`, `assets`, `audit_logs` | asset must exist and not already be disposed, must have no active allocation, disposal date past-or-today and not before the asset's purchase date, disposal value ≥ 0, reason required | `RoleAccessUtil.hasAccess()` called directly (the shared helper, not an inline reimplementation — [DisposeAssetServlet.java:56](src/main/java/com/mycompany/asset_management_system_ams/DisposeAssetServlet.java:56)), matches `assetOps` (SUPER_ADMIN/ADMIN/ASSET_MANAGER) | Yes — `DISPOSE` on success (no `DISPOSE_BLOCKED`-style logging on the several rejection paths, a smaller gap than Modules 4-6/9's thorough standard but not absent entirely — the redirects themselves carry specific error codes) | Yes — with **correctly HTML-escaped** free-text fields throughout ([DisposeAssetServlet.java:197-209](src/main/java/com/mycompany/asset_management_system_ams/DisposeAssetServlet.java:197)) | `?error=invaliddate/failed/alreadydisposed/allocated/server` | Code | **CODE LOOKS CORRECT, BUT see Finding 1** | **High (governance gap, not a security vulnerability)** | **This servlet calls `AssetDAO`'s full 6-argument `disposeAsset(assetId, disposalDate, disposalReason, disposalValue, userId, disposalReason)` overload with the real acting `userId` as `approvedBy` — this resolves the open concern flagged in Module 4 about the single-argument convenience overload's hardcoded `approvedBy=1`: that overload is confirmed, via a full-codebase grep, to have zero callers anywhere. Not a live bug, but worth removing as dead/misleading code (same recommendation as Module 5's dead `AssetAllocationDAO.returnAllocation()`).** |

### Finding 1 (High — governance/control gap, not a defect) — Disposal is a single-step, unapproved, irreversible action, despite a schema built for a full approval workflow

`asset_disposal.disposal_status` is defined as `enum('PENDING','APPROVED','COMPLETED','REJECTED') DEFAULT 'PENDING'` ([schema.sql:55](schema.sql:55)) — a schema clearly designed for a maker-checker approval lifecycle (someone proposes a disposal, it sits `PENDING`, a second party `APPROVE`s or `REJECT`s it, and only then does it become `COMPLETED`). In practice, **`AssetDAO.disposeAsset()`'s INSERT hardcodes `disposal_status` to `'COMPLETED'` immediately** (confirmed in Module 4's original read: `"...VALUES (?, ?, ?, ?, ?, ?, 'COMPLETED', ?)"`), and a full-codebase search for `disposal_status` finds **exactly one reference in the entire application** — that same hardcoded INSERT. There is no servlet, DAO method, or JSP anywhere that ever reads, sets, or transitions through `PENDING`/`APPROVED`/`REJECTED`. **Any single user holding SUPER_ADMIN/ADMIN/ASSET_MANAGER can unilaterally, instantly, and (per §3) irreversibly dispose of any eligible asset in one form submission, with no second-person sign-off, despite the data model being explicitly built to support one.** This is a materially different situation from Module 7's Physical Verification finding — that was a *broken* approval gate (code exists, references a value that can never match); this is an approval gate that was **apparently designed but never implemented at all**, leaving disposal — an inherently high-consequence, typically-audited financial/asset-write-off action in a real organization — as a single-actor action. This is not a security vulnerability (RBAC is correctly enforced for who *can* dispose), but it is a real production-readiness/internal-controls gap for a system managing organizational (here, railway/public-sector) assets, where disposal of capital equipment would ordinarily require independent authorization separate from the person recording it.

---

## 3. Business Workflow / Lifecycle Check

- **Disposal preconditions are correctly and redundantly enforced**: `DisposeAssetServlet` checks `asset.getAssetStatus()`/`hasExistingDisposal()`/`hasActiveAllocation()` before calling the DAO, and `AssetDAO.disposeAsset()` **independently re-checks all of the same conditions again inside its own transaction** (per Module 4's original read: `currentStatus.isEmpty() || "DISPOSED".equalsIgnoreCase(currentStatus) || hasActiveAllocation(con, assetId) || hasExistingDisposal(con, assetId)`) — genuine defense-in-depth against a TOCTOU race between the servlet's pre-check and the actual write, consistent with this codebase's better-engineered modules.
- **`uk_disposal_asset_id` UNIQUE KEY** ([schema.sql:60](schema.sql:60)) provides a DB-level backstop against a duplicate disposal record for the same asset, mirroring Module 12's strong three-layer pattern (though here it's two layers — application check + DB constraint — rather than three, since no row-lock/`FOR UPDATE` was observed in the disposal path specifically).
- **No "undo disposal" / restore-from-disposal path found anywhere** — combined with Finding 1, this means a single-actor, unapproved action is also permanent. A mistaken disposal (wrong asset selected, wrong reason) has no in-application recovery path; the only remedy would be a direct database correction outside the application, which itself would bypass the audit trail this module otherwise carefully builds.
- **Disposal-date-not-before-purchase-date** check is a real, sensible plausibility guard, consistent with the temporal-consistency care already seen in Module 12.

---

## 4. Data Model Check

`asset_disposal` ([schema.sql:47-64](schema.sql:47)): `disposal_id, asset_id (UNIQUE), disposal_date, disposal_reason (enum), disposal_value, approved_by, approved_date, disposal_status (enum, vestigial per Finding 1), remarks, created_at, updated_at`.

- `disposal_reason` enum (`END_OF_LIFE/BEYOND_ECONOMIC_REPAIR/OBSOLETE/DAMAGED/LOST/OTHER`) is a reasonable, complete set for a real asset write-off process.
- `approved_by`/`approved_date` **are** correctly populated (via the real `userId` passed through from the servlet, per §2/M1) — despite `disposal_status` never actually reaching `'APPROVED'`, the *who and when* of the (self-)approval is captured, which partially mitigates Finding 1's audit-trail concern even though the workflow-control concern stands.
- No `disposal_method`/`buyer_reference`/`auction_reference` fields — for a full "Auction/Sale" capability (mentioned as a candidate module in the Phase-0 discovery prompt but not found implemented anywhere in this codebase), this table would need to be extended; as it stands, disposal only records *that* and *why* an asset left service, not *how* it was physically/financially disposed of (scrapped, sold, donated, etc.) beyond the coarse `disposal_reason` enum.

---

## 5. Status Model Check

- `assets.asset_status = 'DISPOSED'` is a correct terminal state — no code path found anywhere in the audit so far that transitions an asset *out* of `DISPOSED` (consistent across Modules 4, 5, 10, 12's independent guards, all of which treat `DISPOSED` as a hard stop).
- `asset_disposal.disposal_status` is present but inert (Finding 1) — effectively a single-value field in practice (`'COMPLETED'`, always).

---

## 6. RBAC & Security Check

- **CSRF**: app-wide gap; disposal has no re-authentication requirement, making it a clean CSRF target for a privileged session, and — unlike most other modules' CSRF exposure — this one triggers an **irreversible** action (§3), raising its practical severity above a typical CSRF-exposed CRUD action.
- **RBAC enforcement**: correct, uses the shared `RoleAccessUtil.hasAccess()` helper directly (a better pattern than several other modules' inline reimplementation).
- **Email HTML escaping is correctly done here** — this module is confirmed (via its own code comment) as the *origin* of the `HtmlEscapeUtil` fix that Module 9's `DeleteEmployeeServlet` later cited and applied, but which Modules 10 and 12 never received. Useful confirmation for the final report: the fix demonstrably exists and was applied to at least two modules (this one and Employees), but not swept across the whole codebase.
- **IDOR**: none found — `assetId` flows through parameterized, appropriately role-gated queries with no ownership scoping needed (disposal is an organization-wide action, not a per-user one).

---

## 7. Audit Log & Data Integrity Check

- Success is audit-logged with a complete, informative message; **rejection paths are not individually audit-logged** (unlike Modules 4-6/9's standard) — a smaller monitoring gap, worth noting since disposal's high consequence makes even *attempted* disposals of ineligible assets (e.g., someone repeatedly trying to dispose of an actively-allocated asset) a signal worth capturing.
- **Finding 1 is the dominant integrity/control concern**: the `approved_by`/`approved_date` columns are populated but represent self-approval (the same actor who initiates the disposal is recorded as having approved it, since there is no second-party step), which weakens their value as genuine authorization evidence even though the columns are technically populated correctly.

---

## 8. Missing Features / Gaps

- **Finding 1**: no real approval workflow despite the schema being built for one.
- No restore/undo path for a mistaken disposal.
- No rejection-path audit logging.
- No disposal-method/proceeds/buyer tracking beyond the coarse reason enum — no Auction/Sale capability found anywhere in the codebase (confirmed absent, not just unaudited, per the Phase-0 discovery sweep).
- Dead single-argument `AssetDAO.disposeAsset(int assetId)` overload (confirmed zero callers) — same class of cleanup item as Module 5's dead `returnAllocation()`.

---

## 9. Advanced Feature Recommendations

- **P1** — Implement the maker-checker approval workflow the schema already models: a disposal request enters `PENDING`, a second authorized user (or a role distinct from the requester) must `APPROVE`/`REJECT` before `disposal_status` becomes `COMPLETED` and the asset's `asset_status` actually flips to `DISPOSED` — this is the single highest-value structural improvement for this module, and notably the schema needs no changes to support it, only application logic.
- **P1** — CSRF token specifically for this endpoint given the irreversibility of the action, even ahead of a general app-wide CSRF fix, given the asymmetric cost of a forged disposal versus most other forged actions in this app.
- **P2** — Add rejection-path audit logging, matching the codebase's stronger-module standard.
- **P2** — Remove the dead single-argument `disposeAsset()` overload.
- **P3** — Extend the data model for disposal method/proceeds/buyer if an Auction/Sale capability is ever wanted.
- **P3** — Consider a bounded "undo" window (e.g., disposal reversible within 24 hours by a SUPER_ADMIN, fully audited) as a pragmatic middle ground short of full approval-workflow implementation.

---

## 10. Test Cases

No dedicated test file found for this module in the Phase-0 inventory.

- [ ] **Functional**: disposing an eligible asset succeeds, sets `asset_status='DISPOSED'`, `condition_status='DAMAGED'`, `service_status='SCRAP_RECOMMENDED'`, and creates one `asset_disposal` row with `approved_by` correctly set to the acting user
- [ ] **Negative/Boundary**: disposing an already-disposed asset is blocked (`alreadydisposed`)
- [ ] Disposing an asset with an active allocation is blocked (`allocated`)
- [ ] Disposal date before the asset's purchase date is rejected
- [ ] **Regression test documenting Finding 1**: confirm `disposal_status` is `'COMPLETED'` immediately upon a single POST, with no intermediate `PENDING`/`APPROVED` state ever observable (documents the current, undesired behavior pending a fix)
- [ ] **RBAC**: EMPLOYEE/AUDITOR/DEPARTMENT_HEAD cannot POST to `DisposeAssetServlet`
- [ ] **Security**: direct `curl -X POST /DisposeAssetServlet` with a valid ASSET_MANAGER session and no CSRF-equivalent token succeeds and irreversibly disposes a real asset (documents the elevated-severity CSRF exposure given the action's irreversibility)
- [ ] **Concurrency**: two simultaneous disposal attempts for the same asset — confirm the `UNIQUE KEY` on `asset_id` prevents a duplicate `asset_disposal` row even without an explicit row lock in this path
- [ ] **DB integrity**: confirm no code path anywhere can transition an asset's `asset_status` away from `'DISPOSED'` once set

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 6 | The action itself is complete and well-validated; the approval half of the intended workflow is entirely absent |
| Lifecycle support | 5 | Correctly guards against double/invalid disposal, but the missing approval step and lack of any undo make this the weakest lifecycle story of the asset-state-changing modules audited so far |
| Data integrity | 7 | Good constraint usage (`UNIQUE KEY`), correctly populated approval-metadata columns (even if the workflow around them is vestigial) |
| UX | 7 | Clear error codes; correctly escaped notification email (a genuine strength, and the demonstrated origin of a fix other modules should have received) |
| Validation | 8 | Thorough, redundant (servlet + DAO) precondition checks |
| RBAC | 8 | Correct, uses the shared helper directly |
| Security | 6 | No CSRF (shared gap, elevated severity here given irreversibility); otherwise clean |
| API integration | 7 | Consistent conventions |
| DB integrity | 7 | Good constraint backing; no row-lock observed for the disposal path specifically (lower than Module 12's benchmark) |
| Auditability | 6 | Success well-logged; rejection paths are not |
| Reliability | 7 | Redundant precondition checks are a real strength |
| Performance | 7 | No inefficiencies observed |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Covered under Module 24 |

**Overall status: MAJOR WORK REQUIRED**

The disposal action itself is competently engineered — well-validated, appropriately RBAC-gated, and the notification path is a demonstrated example of the codebase's HTML-escaping fix at its point of origin. But Finding 1 is a genuine production-readiness concern for a real organization: an irreversible, financially-consequential action (writing off an organizational asset) can be performed unilaterally by any one of three roles, with no second-party authorization, despite the database schema being explicitly designed to support one. For a system intended to manage real public-sector railway assets, this is a control gap worth prioritizing before go-live, not merely a nice-to-have enhancement.
