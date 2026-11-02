# Module 7 Audit — Physical Verification / Audit

**Scope:** Scheduled physical asset audits (duty scheduling, verification submission/draft, review/approve/reject, exception reporting/export) — `AddPhysicalVerificationServlet`, `ReviewPhysicalVerificationServlet`, `SchedulePhysicalVerificationDutyServlet`, `ExportPhysicalVerificationReportServlet`, `physical_verification.jsp`, `view_verification.jsp`.
**Verification layers used:** (a) static code reading — full for the servlets; the central finding below is derived directly and unambiguously from comparing the DB schema's enum definition against the servlet's and JSP's own literal string comparisons, so it is reported with high confidence despite not having run the app. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| Physical Verification (hub) | [physical_verification.jsp](src/main/webapp/physical_verification.jsp) | Duty list, schedule-new-duty form, verification entry, round/status filters |
| View Verification | [view_verification.jsp](src/main/webapp/view_verification.jsp) | Single verification record detail + Approve/Reject controls |

No separate dedicated Add/Edit JSPs — verification entry and duty scheduling both appear to be embedded within `physical_verification.jsp` per the file inventory (not independently confirmed by file listing this pass beyond what's referenced by the servlets read).

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| G1 | Schedule Verification Duty | physical_verification.jsp form | native POST | `POST /SchedulePhysicalVerificationDutyServlet` | [SchedulePhysicalVerificationDutyServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/SchedulePhysicalVerificationDutyServlet.java:23) | `physical_verification_duties`, `physical_verification_rounds`, `audit_logs` | officer required, `scheduledFrom` valid & not in the past, `scheduledTo` (defaults to `scheduledFrom` if blank) not in the past and not before `scheduledFrom` | BE: SUPER_ADMIN/ADMIN/ASSET_MANAGER ([SchedulePhysicalVerificationDutyServlet.java:289](src/main/java/com/mycompany/asset_management_system_ams/SchedulePhysicalVerificationDutyServlet.java:289)), matches `RoleAccessUtil`'s `assetOps` mapping for this endpoint | Yes (not fully traced, pattern consistent with the rest of the module) | Not confirmed this pass | `?error=scheduleAccessDenied/selectOfficer/invalidFromDate/pastDateBlocked/invalidDateRange/dutyTableMissing` | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Same schema-defensive `tableExists`/column-detection style as the rest of this module |
| G2 | Submit / Save Draft Verification | physical_verification.jsp verification entry form | native POST | `POST /AddPhysicalVerificationServlet` (action=submit or draft) | [AddPhysicalVerificationServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/AddPhysicalVerificationServlet.java:22) | `asset_physical_verification`, `assets`, `physical_verification_duties`, `audit_logs` | asset + officer required, status must be one of the recognized enum values, duty must not already be `SUBMITTED`/`COMPLETED` | BE: SUPER_ADMIN/ADMIN/ASSET_MANAGER (`isAllowedSubmitter`, [AddPhysicalVerificationServlet.java:542](src/main/java/com/mycompany/asset_management_system_ams/AddPhysicalVerificationServlet.java:542)) — narrower than the page's own view-access list (which also includes AUDITOR/DEPARTMENT_HEAD per Module 2's inventory notes — correctly separates who can *view* from who can *submit*) | Yes — `PHYSICAL_VERIFICATION_SUBMITTED`/`PHYSICAL_VERIFICATION_DRAFT` | Not found in this servlet | `?error=selectAsset/selectOfficer/invalidStatus/tableMissing/roundError/officerDepartmentMissing/dutyLocked/saveFailed` | Code | **CODE LOOKS CORRECT, BUT see Finding 1 below** | **Medium** | **Both a draft save and a final submit unconditionally call `updateAssetAfterVerification()` ([AddPhysicalVerificationServlet.java:204](src/main/java/com/mycompany/asset_management_system_ams/AddPhysicalVerificationServlet.java:204), outside any `isSubmitFinal` check) — this immediately mutates the live `assets.asset_status`/`service_status`/`last_physical_verification_date` from a verifier's own not-yet-final, not-yet-reviewed draft observation. Concretely: saving a *draft* verification with `verifiedStatus=DAMAGED` flips the real asset's `service_status` to `NEEDS_ATTENTION` immediately, visible system-wide, before the verifier has even clicked Submit, let alone before anyone has reviewed it.** |
| G3 | Approve / Reject Verification | [view_verification.jsp:571](src/main/webapp/view_verification.jsp:571) buttons | native POST | `POST /ReviewPhysicalVerificationServlet` | [ReviewPhysicalVerificationServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/ReviewPhysicalVerificationServlet.java:17) | `asset_physical_verification` | `verificationId` required, action determines APPROVED/REJECTED | BE: SUPER_ADMIN/ADMIN/ASSET_MANAGER ([ReviewPhysicalVerificationServlet.java:35](src/main/java/com/mycompany/asset_management_system_ams/ReviewPhysicalVerificationServlet.java:35)) | Would log `PHYSICAL_VERIFICATION_APPROVED`/`_REJECTED` **if it were ever reached** | None found | `?error=reviewFailed` (this is, per Finding 2, the *only* outcome this control can ever produce) | Code | **BROKEN** | **Critical** | **See Finding 2 — the entire Approve/Reject workflow is unreachable both in the UI and, independently, in the backend guard.** |
| G4 | Export Physical Verification Report | physical_verification.jsp → `ExportPhysicalVerificationReportServlet` | native GET | `GET /ExportPhysicalVerificationReportServlet` | not read in full this pass | `asset_physical_verification` (read) | — | `RoleAccessUtil` maps this to `reportExportOps` | n/a | n/a | Not assessed | Code | Not audited this pass | — | Deep dive deferred to Module 24 (Reports & Exports) |

---

## 3. Business Workflow / Lifecycle Check

This module is the clearest concrete example found so far of the audit methodology's core directive — "trace it end-to-end, don't conclude a button works because it renders or is clickable" — actually catching a completely broken workflow.

### Finding 2 (Critical) — The entire Physical Verification Review (Approve/Reject) workflow is non-functional

`asset_physical_verification.review_status` is defined in the schema as `enum('SUBMITTED','REVIEWED','APPROVED','REJECTED') NOT NULL DEFAULT 'SUBMITTED'` ([schema.sql:110](schema.sql:110)) — **there is no `'PENDING'` value in this enum, and no verification record can ever have `review_status = 'PENDING'`** (every new row defaults to `'SUBMITTED'`). However:

- [view_verification.jsp:571](src/main/webapp/view_verification.jsp:571) only renders the Approve/Reject buttons `if (canManageVerification && "PENDING".equalsIgnoreCase(reviewStatus))` — since `reviewStatus` is read straight from the `review_status` column and can never literally equal `"PENDING"`, **these buttons never appear in the UI for any real verification record.**
- Independently, [ReviewPhysicalVerificationServlet.java:71](src/main/java/com/mycompany/asset_management_system_ams/ReviewPhysicalVerificationServlet.java:71) guards its `UPDATE` with `WHERE verification_id = ? AND review_status = 'PENDING'` — even if a user bypassed the UI and POSTed directly to this servlet with a valid `verificationId`, the `WHERE` clause can never match any row, so `rowsUpdated` is always `0`, the transaction rolls back, and the response is always `view_verification.jsp?id=...&error=reviewFailed`.

Both the UI trigger and the backend enforcement independently reference the same nonexistent status value, so this is not a case of "the button is hidden but the API works" or vice versa — **the feature is completely dead on both sides**, confirmed by direct comparison of the schema enum against two independent string-literal comparisons in the code, with no ambiguity requiring runtime confirmation. This means: **no physical verification submission can ever be formally approved or rejected through this application.** Given this module's own stated purpose (per the Phase-0 inventory: "Scheduled physical asset audits, **exception reconciliation**"), this defeats the module's core function — verifications can be submitted and will affect asset status (Finding 1), but the compliance sign-off/exception-reconciliation step that is supposed to follow can never actually happen. The likely root cause: the code was written against an intended `review_status` value of `'PENDING'` (a natural, conventional name) at some point when the schema's actual default/initial value is `'SUBMITTED'` instead — a naming mismatch introduced during development that was never caught because nothing in the UI or automated tests exercises this specific state comparison.

### Finding 1 (Medium) — Draft saves have the same production side-effects as final submissions

Restated from §2/G2: `updateAssetAfterVerification()` runs unconditionally regardless of whether the action was `submit` or a draft save. Combined with Finding 2 (review can never happen), this means: **once a verifier saves even a draft entry, the live asset record is permanently changed with no possible corrective review step** — a mistaken or premature draft observation has the same real-world consequence as a fully submitted-and-approved one, and there is no way (through this application) to formally reject it and have that rejection reflected back onto the asset.

### Other lifecycle observations

- **Duty locking is correctly enforced**: `AddPhysicalVerificationServlet` blocks further verification entries once the associated duty's status is `SUBMITTED`/`COMPLETED` ([AddPhysicalVerificationServlet.java:135-141](src/main/java/com/mycompany/asset_management_system_ams/AddPhysicalVerificationServlet.java:135)) — a real, working guard against editing a verification round's entries after the assigned officer has finished.
- **Verification round auto-provisioning**: if no round is supplied, the servlet attempts to find/create a default round ([AddPhysicalVerificationServlet.java:103-109](src/main/java/com/mycompany/asset_management_system_ams/AddPhysicalVerificationServlet.java:103)) rather than failing outright — reasonable resilience.
- **Asset status mapping from verification outcome** (`updateAssetAfterVerification`, [AddPhysicalVerificationServlet.java:929](src/main/java/com/mycompany/asset_management_system_ams/AddPhysicalVerificationServlet.java:929)) is a sensible, well-thought-out mapping (`VERIFIED→SERVICEABLE`, `DAMAGED→NEEDS_ATTENTION`, `UNDER_REPAIR→UNDER_MAINTENANCE/UNDER_REPAIR`, `NOT_FOUND`/`LOCATION_MISMATCH`/`EMPLOYEE_MISMATCH`/`NEEDS_REVIEW`→`NEEDS_ATTENTION`) — the *design* of what should happen to an asset on each outcome is good; the problem is purely *when* it happens (immediately, unconditionally) versus the review step that should gate it but never can (Finding 2).

---

## 4. Data Model Check

- `asset_physical_verification` ([schema.sql:98-122](schema.sql:98)): well-structured — links to round, duty, asset, verifier, actual observed location/employee (for mismatch detection), officer + officer's department, a 7-value `verified_status` enum covering realistic audit outcomes, and the broken 4-value `review_status` enum (Finding 2).
- `physical_verification_duties` ([schema.sql:614-632](schema.sql:614)): `duty_status` enum `SCHEDULED/IN_PROGRESS/SUBMITTED/COMPLETED/CANCELLED` — five states, all named consistently and sensibly (no `PENDING`-vs-`SUBMITTED` naming mismatch here, unlike the verification table).
- `physical_verification_rounds` ([schema.sql:635-648](schema.sql:635)): `status` enum has an unusually large set of overlapping-looking values (`SCHEDULED,IN_PROGRESS,COMPLETED,CANCELLED,ACTIVE,OPEN,PENDING` — seven values where several appear to mean similar things, e.g. `SCHEDULED`/`OPEN`/`PENDING` or `ACTIVE`/`IN_PROGRESS`) — this looks like the same kind of naming drift that produced Finding 2, just contained (so far as traced this pass) to the enum definition rather than confirmed broken code; worth a targeted check of whichever code sets/reads `physical_verification_rounds.status` to confirm it isn't hitting the identical class of bug.
- The extensive `tableExists`/`columnExists`/`isWritableColumn`/`isColumnNullable`/`getSafeColumnValue` helper methods throughout `AddPhysicalVerificationServlet` (§ code structure, not fully quoted) represent real, deliberate engineering effort to make this specific module resilient to schema drift — a stronger defense than most of the rest of the app has against the `role_id`-style mismatches found in Modules 1-3. It is a genuine irony that this same module, despite that effort, contains the single clearest schema-vs-code mismatch found in the entire audit so far (Finding 2) — the defensive tooling guards against *missing columns*, not against a column existing but being compared to the *wrong string value*, which is a different failure mode entirely.

---

## 5. Status Model Check

- `verified_status`: 7-value enum, all reachable and mapped to sensible asset-status consequences (§3).
- `duty_status`: 5-value enum, consistently named, correctly guarded against edits after `SUBMITTED`/`COMPLETED`.
- **`review_status`: the only status field in this module (and the clearest one found in the whole audit so far) with a confirmed, code-verified, unreachable-value defect (Finding 2).** The intended state machine (`SUBMITTED → APPROVED` or `SUBMITTED → REJECTED`, with an unused `REVIEWED` value in between whose purpose isn't clear from what was read this pass) can never progress past its initial state through the application.

---

## 6. RBAC & Security Check

- **CSRF**: app-wide gap applies to all three POST actions in this module.
- **RBAC enforcement**: consistently correct and appropriately layered — submission/scheduling restricted to SUPER_ADMIN/ADMIN/ASSET_MANAGER, viewing extended to AUDITOR/DEPARTMENT_HEAD per Module 2's inventory notes, matching `RoleAccessUtil`'s dedicated `verificationViewOps` list. No drift found.
- **No security vulnerability in Finding 2** — it is a pure functional defect (the feature is unreachable, not insecurely reachable), but it is worth noting that a completely broken approval gate on an "exception reconciliation" process is itself a **compliance/control risk** even though it isn't a classic security hole: it means every physical verification, however submitted, becomes permanent and unreviewable, with no formal check on the submitter's own work.
- IDOR: not specifically probed this pass; `verificationId`/`assetId` parameters flow into parameterized queries throughout.

---

## 7. Audit Log & Data Integrity Check

- Submission/draft actions are audit-logged; the (unreachable) approve/reject action has audit-logging code present too, though it can never execute (Finding 2).
- **Data-integrity consequence of Finding 1+2 together**: the `assets` table can accumulate status changes driven by verification submissions that are permanently stuck in `SUBMITTED` review state, with no way to distinguish (from the asset's perspective) a properly-vetted status change from an unreviewed, possibly-mistaken one — the review step exists in the data model specifically to provide that distinction, and it cannot function.

---

## 8. Missing Features / Gaps

- **The Review (Approve/Reject) workflow, as documented above, is entirely non-functional** — the single largest gap in this module.
- No corrective/rollback mechanism for an asset status change caused by a since-corrected or since-rejected verification (moot until Finding 2 is fixed, but worth designing in at the same time — a `REJECTED` verification should arguably revert the asset's status change it caused, not just be relabeled).
- `physical_verification_rounds.status`'s apparently-overlapping enum values (§4) warrant the same kind of check that surfaced Finding 2, not yet performed.

---

## 9. Advanced Feature Recommendations

- **P0** — Fix Finding 2: either change `ReviewPhysicalVerificationServlet.java:71` and `view_verification.jsp:571` to check for `review_status = 'SUBMITTED'` (matching the actual schema default), or migrate the schema/enum to include and default to `'PENDING'` if that was the originally intended semantic — either fix restores the entire review workflow; this should be the single highest-priority fix identified across the whole audit so far, given how completely it disables a module explicitly built for compliance/exception reconciliation.
- **P0** — Gate `updateAssetAfterVerification()` behind `isSubmitFinal` (Finding 1) so draft saves no longer have live production side-effects, once Finding 2 makes the review step reachable and meaningful — the two fixes are complementary: the asset should arguably only change on submit, and ideally only be treated as authoritative after review/approval.
- **P1** — Design and implement a rollback path for a `REJECTED` verification's asset-status side-effects.
- **P1** — Audit `physical_verification_rounds.status`'s reader/writer code for the same value-mismatch risk pattern found in Finding 2.
- **P2** — Notification on Approve/Reject (not found in `ReviewPhysicalVerificationServlet` — the submitter currently has no way to learn their verification was reviewed, once the feature works).
- **P3** — CSRF tokens (shared app-wide recommendation).

---

## 10. Test Cases

No dedicated test file for this module was found in the Phase-0 inventory — directly relevant, since a basic integration test exercising "submit a verification, then approve it" would have caught Finding 2 immediately.

- [ ] **Regression test for Finding 2 (highest priority in this entire audit series so far)**: submit a verification (creates a row with `review_status='SUBMITTED'`), then POST to `ReviewPhysicalVerificationServlet` with `action=approve` — assert `review_status` becomes `APPROVED` (expected to currently **fail** — `rowsUpdated` will be 0)
- [ ] Confirm the Approve/Reject buttons render on `view_verification.jsp` for a freshly-submitted verification (expected to currently **fail** — they never render, since `reviewStatus` is never literally `"PENDING"`)
- [ ] **Regression test for Finding 1**: save a *draft* verification with `verifiedStatus=DAMAGED` for a `SERVICEABLE` asset — assert the asset's `service_status` is unchanged until final submission (expected to currently **fail** — it changes immediately on draft save)
- [ ] **Functional**: submitting a verification for a duty already in `SUBMITTED`/`COMPLETED` status is blocked (`dutyLocked`) — this one is expected to **pass**, confirm as a regression guard
- [ ] Schedule a duty with `scheduledFrom` in the past — rejected
- [ ] Schedule a duty with `scheduledTo` before `scheduledFrom` — rejected
- [ ] **RBAC**: AUDITOR/DEPARTMENT_HEAD can view but cannot submit a verification or schedule a duty; EMPLOYEE cannot reach any of these three servlets
- [ ] **Security**: direct `curl -X POST /ReviewPhysicalVerificationServlet` with a valid ASSET_MANAGER session and a real `verificationId` — currently always returns `reviewFailed` regardless of session validity, which is itself worth asserting as the *current* (broken) behavior until Finding 2 is fixed
- [ ] **DB integrity**: confirm no row in a live `asset_physical_verification` table has ever had `review_status` progress past `SUBMITTED` (would empirically confirm Finding 2's real-world impact, if a live database is available to inspect)

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 3 | Submission and scheduling work; the review/approval half of the module's core purpose is entirely non-functional |
| Lifecycle support | 3 | Duty-locking is solid; the submit→review→resolve lifecycle cannot complete past submission |
| Data integrity | 4 | Asset status is mutated by unreviewed, unreviewable draft/submitted data with no correction path |
| UX | 4 | The missing Approve/Reject buttons would present as "nothing to review" to an operator, with no error shown — a silent, confusing gap rather than a visible bug |
| Validation | 7 | Input validation on both servlets (dates, required fields, status enum) is solid |
| RBAC | 8 | Correct, consistent, appropriately layered by view vs. submit vs. review privilege |
| Security | 6 | No CSRF (shared gap); Finding 2 is a functional defect, not an access-control weakness |
| API integration | 5 | Otherwise-consistent conventions undermined by the one completely dead endpoint |
| DB integrity | 5 | Well-designed schema undermined by the enum-value/code mismatch |
| Auditability | 5 | Logs what does happen; can never log an approval/rejection since it can never occur |
| Reliability | 6 | Strong defensive schema-adaptive coding elsewhere in this module, ironically not the category of bug that actually broke it |
| Performance | 7 | No inefficiencies observed |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Covered under Module 24 |

**Overall status: NOT READY**

This module cannot be considered production-ready: its stated core purpose — exception reconciliation via a reviewed, approved verification process — is completely blocked by a single, high-confidence, code-verifiable defect (Finding 2). Everything upstream of the review step (scheduling, submission, asset-status mapping logic) is well-engineered, which makes the missing link more notable, not less consequential — a verifier can complete their entire workflow, believe they've done their job, and the "audit trail" this module exists to produce can never receive the sign-off that gives it authority.
