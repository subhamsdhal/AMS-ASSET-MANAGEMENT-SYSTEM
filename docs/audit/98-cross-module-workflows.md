# Phase 2 — Cross-Module End-to-End Workflow Traces

Synthesized from the 28 individual module audits (`audit/01-*.md` through `audit/28-*.md`) — no new code exploration was required for this phase beyond what those audits already established; each workflow below cites the specific module(s) and findings it draws on.

---

## 1. Purchase → Receive → Register → Tag → Assign

| Step | Module | Status |
|---|---|---|
| Purchase | **No module exists** | There is no Procurement/Purchase Order/Requisition module anywhere in this codebase (confirmed absent from the Phase-0 discovery sweep across all 28 audited modules) |
| Receive | **No module exists** | No Goods Receipt / three-way-match capability found |
| Register | Module 4 (Asset Registry) | Works — `AddAssetServlet` is the best-validated servlet in the entire audit |
| Tag | Module 8 (QR/Barcode) | Works — cryptographically sound token generation, correctly synced |
| Assign | Module 5 (Asset Allocation) | Works — strongest concurrency protection in the audit (`FOR UPDATE` row locks) |

**Failure point**: this workflow **does not exist end-to-end in this application**. An asset simply comes into being via a manual "Add Asset" form entry (Module 4) — `purchase_date`/`purchase_cost`/`vendor_id` are recorded as free-standing historical fields typed in by whoever registers the asset, with no upstream purchase order, no goods-receipt confirmation, and no three-way match against an actual procurement transaction. For an organization that needs genuine procurement traceability ("which PO did this asset come from, was it fully paid, did receiving confirm the quantity/condition against the order"), this is a complete capability gap, not a bug in an existing flow. Register→Tag→Assign itself works cleanly and is well-engineered (both Modules 4 and 5 are among the strongest audited).

**Recovery mechanism**: N/A — nothing to recover, since the missing steps were never implemented rather than broken.

---

## 2. Request → Approve → Assign → Acknowledge

| Step | Module | Status |
|---|---|---|
| Request | Module 6 (Asset Requests) | Works — real IDOR protection, SQL-layer defense-in-depth |
| Approve | Module 6 | Works — genuine transition-guard (`PENDING→APPROVED`), with one caveat (Finding 2: malformed status can reset to PENDING) |
| Assign (Fulfill) | Module 5 / Module 6 boundary | **Broken link** |
| Acknowledge | **No module exists** | No employee receipt-confirmation step found anywhere |

**Failure point**: Module 6's own audit confirmed `asset_requests.fulfilled_asset_id` — the column specifically meant to link an approved/fulfilled request to the actual asset allocation created to satisfy it — **is never populated by any code path**. `UpdateRequestStatusServlet` can mark a request `FULFILLED`, but nothing in that action actually creates the corresponding `asset_allocation` row, and nothing in Module 5's `AddAllocationServlet` reads or updates `asset_requests` at all. **The two halves of this workflow are operationally connected only by an ops user remembering to do both steps manually** — approve the request in one screen, then separately go create the allocation in another screen — with no system-enforced or system-recorded link between them. A request can be marked `FULFILLED` with no corresponding allocation ever created, or an allocation can be created with no request ever referencing it, and the system would show no inconsistency because nothing cross-checks the two.

**Acknowledge**: no step anywhere in Module 5 or 6 has the employee confirm receipt of an allocated asset — allocation is a unilateral admin/asset-manager action with no employee-side sign-off.

**Recovery mechanism**: none — this requires a structural fix (either have the Fulfill action itself create the allocation, or have the allocation-creation flow accept an optional source-request reference and write it back).

---

## 3. Transfer Request → Approval → Physical Transfer → New Custodian

| Step | Module | Status |
|---|---|---|
| Transfer Request (employee preference) | Module 19 (`SubmitEmployeeTransferPreferenceServlet`) | Works — genuine, double-layered IDOR protection, explicitly non-binding |
| Approval | Module 19 (`TransferEmployeeServlet`) | **Flattened, not a distinct step** |
| Physical Transfer (asset retain/return decision) | Module 19 | Works — fail-safe defaults, reuses Module 12's well-guarded return logic |
| New Custodian | Module 19 (`updateEmployeeDepartment`) + Module 5 | Works — department correctly updated, notification correctly sent to the *old* department head |

**Assessment**: this is one of the best-functioning cross-module chains in the entire application (Module 19 was rated **PRODUCTION READY**, the strongest score of any mutating module). The workflow is flatter than the four-step model implies — there's no distinct, separately-recorded "approval" step; the ADMIN/SUPER_ADMIN/DEPARTMENT_HEAD who processes `TransferEmployeeServlet` performs the review and the execution in one atomic action, with the employee's own prior preference (if any) pre-filled but always overridable. This is a reasonable design choice for an internal HR-adjacent action, not a gap — no failure point found in this chain.

**Recovery mechanism**: correctly handled — a partial multi-asset transfer failure aborts before the department change commits, and completed sub-steps (individual asset returns) are safely idempotent and retry-safe, per Module 19's own documented reasoning.

---

## 4. Maintenance Request → Diagnose → Repair → Cost → Close

| Step | Module | Status |
|---|---|---|
| Maintenance Request | Module 11 | Works — genuine IDOR protection on creation |
| Diagnose / Repair / Cost | Module 10 (`AddMaintenanceServlet`/`MaintenanceLogDAO`) | Works in isolation — this is one of the most concurrency-safe modules audited |
| Close (Request side) | Module 11 (`UpdateMaintenanceRequestStatusServlet`) | Works, but **not guarded** (Finding 1: no transition guard) |
| **Link between Request and Log** | Module 10 / Module 11 boundary | **Broken link** |

**Failure point**: identical shape to Workflow 2's gap. Module 11's own audit confirmed **no structural link exists between `maintenance_requests` and `maintenance_logs`** — no `maintenance_id` reference on the request, no `request_id` back-reference on the log. An employee reports an issue (Module 11), an ASSET_MANAGER separately logs the actual diagnosis/repair/cost via Module 10's entirely independent `AddMaintenanceServlet`, and then separately marks the original request `COMPLETED` via Module 11 — three actions across two modules with **no system-enforced connection between them**. There is no way to query "which maintenance log resolved request #42," and — compounding this — Module 11's status-transition guard gap means the request's own status history isn't even reliably one-way, so even the weak implicit connection ("the request was marked completed around the same time a log was created") isn't a trustworthy audit signal.

**Recovery mechanism**: none — same structural fix needed as Workflow 2 (a `request_id` FK on `maintenance_logs`, populated when a log is created in response to a specific request).

---

## 5. Employee Exit → Identify Assets → Return → Verify → Clear

| Step | Module | Status |
|---|---|---|
| Employee Exit (Retirement) | Module 19 (`RetireEmployeeServlet`) | Works |
| Identify Assets | Module 19 (queries `AssetAllocationDAO.getAllocationsByEmployeeId`) | Works |
| Return | Module 19 → Module 12 (`AssetReturnDAO.addReturnAndReturnId`) | Works — inherits Module 12's three-layer double-return protection |
| Verify / Clear | Module 19 | **Combined into the retirement action itself, not a distinct step** |

**Assessment**: this is the **strongest workflow found in this entire cross-module trace**. Module 19's `RetireEmployeeServlet` explicitly, by design, forces every currently-`ALLOCATED` asset to be returned as part of the same action — no partial retirement state is possible (the servlet aborts the whole retirement if any asset return fails or is missing a submitted condition). "Verify"/"Clear" aren't separate downstream steps requiring a different actor's sign-off; the retiring admin's own action of confirming a return condition for every asset **is** the verification, and successful completion of `RetireEmployeeServlet` **is** the clearance. This is a deliberate, well-reasoned design (documented in the servlet's own class-level comment) rather than a gap — no failure point found.

**Recovery mechanism**: correctly handled, same reasoning as Workflow 3 — idempotent, retry-safe sub-steps, no possibility of a "retired but still shows custody of an asset" impossible state.

---

## 6. Physical Audit → Scan → Verify → Exception → Reconcile

| Step | Module | Status |
|---|---|---|
| Physical Audit (Schedule Duty) | Module 7 (`SchedulePhysicalVerificationDutyServlet`) | Works |
| Scan / Verify (Submit) | Module 7 (`AddPhysicalVerificationServlet`) | Works, but has its own finding (draft saves mutate the live asset immediately) |
| Exception (a mismatch/damaged/not-found outcome) | Module 7 | Correctly captured in the `verified_status` enum and correctly mapped to asset-status consequences |
| Reconcile (Review → Approve/Reject) | Module 7 (`ReviewPhysicalVerificationServlet`) | **Completely non-functional** |

**Failure point**: this is the single most severe cross-module workflow failure in the entire audit, because unlike Workflows 2 and 4 (a missing *link* between two working halves), here the final step of the chain **cannot execute at all**. Module 7's Finding 2 established, with high confidence directly from the code (not inference): the schema's `review_status` enum is `SUBMITTED/REVIEWED/APPROVED/REJECTED`, but both the UI's button-visibility check and the backend servlet's update guard independently compare against the literal string `"PENDING"` — a value that can never occur. **Every physical verification submission, however it comes out (verified, damaged, location-mismatch, not-found), permanently sits in `SUBMITTED` status with no way to ever formally approve or reject it.** The entire back half of this workflow — the "Exception → Reconcile" step that gives the whole physical-audit process its compliance value — is dead on arrival. Compounding this, Module 7's Finding 1 means the *front* half already has a side effect that the (non-functional) back half was meant to gate: a verifier's draft submission immediately and permanently changes the live asset's status, without ever being reviewed.

**Recovery mechanism**: none currently possible through the application — this requires the direct code fix identified in Module 7 (align the enum value in both the servlet and the JSP).

---

## 7. Warranty Expiry → Notification → Renewal / Claim

| Step | Module | Status |
|---|---|---|
| Warranty Expiry (detection) | Module 14 (`WarrantyAlertScheduler`) | Works |
| Notification | Module 14 | Works — dedup'd, rate-limited, correctly routed |
| Renewal | Module 14 (`RenewAssetWarrantyServlet`) | Works — flexible, well-validated, transactionally atomic |
| Claim | **No module exists** | No warranty-claim-filing capability found (only renewal) |

**Assessment**: alongside Employee Retirement (Workflow 5), this is the **other fully-working, well-engineered chain** in the cross-module trace, and the only one of the eight where all implemented steps function correctly with no broken links. Module 14 was the first module in the entire audit to earn a full **PRODUCTION READY** score, and this scheduler is explicitly documented as a deliberate fix for a real, previously-existing gap (a dead settings field, an uncalled notification template). "Claim" (filing an actual warranty claim with a manufacturer/vendor, as distinct from just extending the expiry date) isn't implemented — a reasonable scope boundary rather than a defect, since a claims process would likely need vendor-facing capabilities this system doesn't otherwise have (no vendor portal, no claim-status tracking table found).

**Recovery mechanism**: N/A — no broken step to recover from.

---

## 8. Retirement → Approval → Disposal → Accounting Update

*(Interpreted as **asset** retirement/disposal, distinct from Workflow 5's employee retirement — this is Module 13's domain.)*

| Step | Module | Status |
|---|---|---|
| Retirement (Disposal trigger) | Module 13 (`DisposeAssetServlet`) | Works — well-validated, redundantly guarded against double-disposal |
| Approval | Module 13 | **Does not exist** |
| Disposal (finalization) | Module 13 | Happens instantly, in the same step as "Retirement" above |
| Accounting Update | **No module exists** | No financial/GL/accounting integration found anywhere in this codebase |

**Failure point**: two distinct gaps stack in this workflow. First, Module 13's Finding 1 established that `asset_disposal.disposal_status` is schema-modeled as a full `PENDING→APPROVED→COMPLETED`/`REJECTED` maker-checker workflow, but the only code path that ever touches it hardcodes `'COMPLETED'` immediately — **there is no approval step between "an ASSET_MANAGER decides to dispose of an asset" and "the asset is permanently disposed."** Second, "Accounting Update" — writing off the asset's book value, generating a disposal/write-off journal entry, reconciling against depreciation — has **no corresponding capability anywhere in this application**. `asset_disposal.disposal_value` is recorded (Module 13), and `assets.depreciation_rate`/`purchase_cost` exist (Module 4), but nothing in this codebase computes accumulated depreciation, posts a disposal entry, or integrates with any external accounting system. For an organization tracking real capital assets, this means disposal has no financial closure step at all — the asset vanishes from the active register with a recorded disposal value, but nothing downstream reconciles that against the books.

**Recovery mechanism**: none — both gaps require net-new capability, not a fix to something broken.

---

## Cross-Module Pattern Summary

Three distinct failure shapes recur across these eight traces, worth calling out explicitly since they point to different kinds of fixes:

1. **Missing upstream/downstream capability** (Workflows 1, 7's claim step, 8's accounting step) — no procurement module, no claims module, no accounting integration. These are scope gaps, not defects; whether they matter depends entirely on whether the organization deploying this system needs those capabilities or handles them in a separate system.
2. **Missing structural link between two otherwise-working modules** (Workflows 2 and 4) — both `asset_requests.fulfilled_asset_id` and the `maintenance_requests`↔`maintenance_logs` relationship are absent, meaning two halves of a logical workflow are only connected by an operator's memory and timing coincidence, not by data. This is the most mechanically fixable category — both need a new FK column and one line of code populating it.
3. **A workflow's final step is completely non-functional** (Workflow 6) — Module 7's review-status bug means Physical Verification's entire compliance purpose (formal sign-off on audit exceptions) cannot occur at all. This is the most urgent of the three categories, since — unlike categories 1 and 2, where the *partial* workflow still delivers real value (assets get registered, requests get approved, maintenance gets logged) — a broken final approval step means the module's core stated purpose is unmet even though every step up to it works.

Two workflows (5 and 7) function essentially as designed, end-to-end, with no broken links — both are worth citing in the final report as evidence of what "correctly engineered" looks like elsewhere in this same codebase, for contrast against the gaps found in the other six.
