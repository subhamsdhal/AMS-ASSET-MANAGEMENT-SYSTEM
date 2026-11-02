# Module 28 Audit — Tunnel / Ops Control

**Scope:** `TunnelControlServlet` (single file, ~237 lines) — a developer/demo convenience feature that launches a local Cloudflare Tunnel process so QR codes generated during local development can be scanned from a real mobile device, plus a manual-URL fallback for Ngrok/custom tunnels. Flagged for investigation in the Phase-0 inventory as "unusual for this to be reachable in production."
**Verification layers used:** (a) static code reading — full. (b)/(c) not performed this pass.

---

## 1. Page & UI Inventory

No dedicated JSP found in the file listing — reached via a settings-adjacent control panel (referenced from `settings.jsp`/`qr_control_center.jsp` per the URL patterns `/TunnelControlServlet` and `/CloudflareTunnelServlet`, both mapped to this one servlet).

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| BB1 | Start Cloudflare Tunnel | (settings UI) | AJAX POST | `POST /TunnelControlServlet` (action=start, provider=cloudflare) | [TunnelControlServlet.startCloudflareTunnel](src/main/java/com/mycompany/asset_management_system_ams/TunnelControlServlet.java:129) | `system_settings` (mobile tunnel URL/provider) | Checks `cloudflared.exe` exists at a hardcoded path before attempting to launch | SUPER_ADMIN/ADMIN only ([TunnelControlServlet.java:47-53](src/main/java/com/mycompany/asset_management_system_ams/TunnelControlServlet.java:47)) | Yes — `UPDATE` on `system_settings` once a tunnel URL is obtained | n/a | Distinct JSON states for not-found/error/starting/running | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | **This servlet spawns a real OS-level child process** (`ProcessBuilder(CLOUDFLARED_PATH, "tunnel", "--url", "http://localhost:8080")`, [TunnelControlServlet.java:142](src/main/java/com/mycompany/asset_management_system_ams/TunnelControlServlet.java:142)) — see §6 for the production-readiness implications of this capability existing in a web-reachable endpoint at all, independent of whether the current implementation is itself exploitable |
| BB2 | Stop Tunnel | (settings UI) | AJAX POST | `POST /TunnelControlServlet` (action=stop) | [TunnelControlServlet.stopTunnel](src/main/java/com/mycompany/asset_management_system_ams/TunnelControlServlet.java:195) | `system_settings` | n/a | SUPER_ADMIN/ADMIN | Yes | n/a | n/a | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | Cleanly terminates the child process (`destroy()` + `waitFor()`) and reverts the saved URL |
| BB3 | Set Manual Tunnel URL | (settings UI) | AJAX POST | `POST /TunnelControlServlet` (action=set_manual) | [TunnelControlServlet.java:78-104](src/main/java/com/mycompany/asset_management_system_ams/TunnelControlServlet.java:78) | `system_settings` | Requires `http://`/`https://` prefix; blocks `<`, `>`, `"`, `'` characters | SUPER_ADMIN/ADMIN | Yes | n/a | `?error=` on invalid URL/characters | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | This value becomes `ams.qr.mobile_tunnel_url`, which per Module 8's `QrUrlUtil` is one of the settings consulted when building the base URL embedded into every newly-generated public QR code — a malicious value here (settable only by an already-privileged SUPER_ADMIN/ADMIN) could redirect future QR scans to an attacker-controlled domain, but this requires an already-compromised or malicious admin account, not an external attacker |

---

## 3. Business Workflow / Lifecycle Check

- **Tunnel state is intentionally global/shared** (`private static Process tunnelProcess`, `private static String currentTunnelUrl`/`tunnelStatus`) — appropriate given this represents a single, server-wide outbound tunnel resource, not a per-user object; one admin starting or stopping it affects the whole application's QR base URL for everyone, which is the correct behavior for what this feature actually is.
- **Clean process lifecycle**: the background reader thread is a daemon (won't block JVM/Tomcat shutdown), `stopTunnelProcess()` is called defensively before starting a new one (preventing orphaned processes accumulating across repeated starts), and `destroy()` (the servlet lifecycle hook) also cleans up the process on undeploy/shutdown.
- **Well-documented prior fix, the same recurring class found throughout this codebase**: `userId` used to be read from the session attribute `"userId"`, but `LoginServlet` only ever sets `"user_id"` — meaning every audit-log entry this servlet wrote was previously attributed to user ID 0 for every real user, now fixed ([TunnelControlServlet.java:56-58](src/main/java/com/mycompany/asset_management_system_ams/TunnelControlServlet.java:56)).

---

## 4. Data Model Check

No dedicated table; writes two keys into `system_settings` (mobile tunnel URL, tunnel provider), consistent with the rest of the settings infrastructure (Module 23).

---

## 5. Status Model Check

Four informal states (`stopped/starting/running/error`, plus a derived `manual` display state) tracked in a plain static string field rather than an enum — low risk given the narrow, single-purpose scope of this servlet, not flagged as a defect.

---

## 6. RBAC & Security Check

- **RBAC is correctly restrictive** (SUPER_ADMIN/ADMIN only) for a feature this operationally significant.
- **No command injection found**: the `ProcessBuilder` arguments are 100% hardcoded constants (`CLOUDFLARED_PATH`, `"tunnel"`, `"--url"`, `"http://localhost:8080"`) — no request parameter reaches the spawned process's command line at all, so there is no injection surface in the current implementation.
- **The manual-URL validation is a basic denylist** (specific characters blocked, scheme prefix required) rather than a strict URL parser/allowlist — adequate for blocking the most obvious injection vectors given the scheme-prefix requirement already rules out `javascript:`/`data:` URIs, but not as rigorous as dedicated URL-validation logic would be; low priority given the action is already restricted to already-fully-trusted admin accounts.
- **The central production-readiness concern for this module is architectural, not a specific code defect**: **a business asset-management web application should not, in a production deployment, retain a web-reachable endpoint capable of spawning arbitrary OS-level child processes** — regardless of how well-locked-down the current single hardcoded command is. This is unambiguously a local-development/demo convenience feature (the hardcoded Windows-only path `C:\Cloudflared\cloudflared.exe`, and its evident purpose — letting a developer demo QR scanning on a real phone without deploying anywhere — both confirm this; the repo root's `RAILWAY_AMS_FINAL_DEMO_CHECKLIST.md`, noted in the Phase-0 inventory, corroborates this same demo-oriented intent). Shipping this capability into a real production environment expands the application's attack surface in a category (arbitrary process execution) that nothing else in this entire 27-module audit comes close to — even Module 23's database restore, the next most powerful capability found, is still confined to SQL executed against the application's own database connection, not general OS process control.

---

## 7. Audit Log & Data Integrity Check

Start/stop/manual-set are all audit-logged with the correct actor attribution (post-fix). No further integrity concerns — this module owns no business data.

---

## 8. Missing Features / Gaps

- No environment/deployment-mode guard (e.g., a check that disables this servlet entirely outside a `development`/`demo` profile) — this is the single most important gap: the feature's own design clearly assumes a local/demo context, but nothing in the code enforces that assumption at runtime.
- Manual URL validation is denylist-style rather than a proper URL parser.

---

## 9. Advanced Feature Recommendations

- **P0 (for any real production deployment)** — Gate this entire servlet behind an explicit environment/deployment-mode flag (e.g., only registered/reachable when a `demo.mode.enabled` or equivalent setting is true, or excluded from the production WAR build entirely) so the process-spawning capability cannot exist in a live, internet-facing deployment regardless of role-based access control — RBAC restricts *who* can use a dangerous capability, but the safer and more robust fix for a capability this categorically different from the rest of the app is to ensure it *doesn't exist* outside the context it was built for.
- **P2** — Replace the manual-URL denylist with a proper URL-parsing validation (e.g., `java.net.URI`, confirm scheme/host structure) for defense-in-depth, even though the current risk is low given the admin-only gate.
- **P3** — Convert the informal status strings to a proper enum for consistency with the rest of the codebase's stricter typing elsewhere.

---

## 10. Test Cases

No dedicated test file found for this module in the Phase-0 inventory — reasonable given its narrow, environment-dependent scope (hard to unit-test process-spawning behavior portably).

- [ ] **RBAC**: non-SUPER_ADMIN/ADMIN roles cannot reach any of the three actions
- [ ] **Functional**: starting a tunnel when `cloudflared.exe` is absent returns a clear "not found" error, not a crash
- [ ] Stopping an already-stopped tunnel is a safe no-op
- [ ] Manual URL with disallowed characters or missing scheme prefix is rejected
- [ ] **Security**: confirm no request parameter can influence the actual `ProcessBuilder` command/arguments (should currently **pass** — everything is hardcoded)
- [ ] **Production-readiness check (the real point of this module's audit)**: confirm with the deployment/ops team whether this servlet is excluded from the actual production build/deployment, or reachable there — this is a process/deployment-configuration question this code-only audit cannot answer definitively, and is the single most important open item for this module

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 8 | Does exactly what it's designed to do, competently |
| Lifecycle support | 8 | Clean process lifecycle management |
| Data integrity | 8 | No integrity concerns; owns no business data |
| UX | 7 | Clear status states and error messaging |
| Validation | 6 | Adequate denylist-style URL validation |
| RBAC | 8 | Correctly restricted to the highest-privilege roles |
| Security | 4 | No exploitable defect found in the current implementation, but the category of capability (arbitrary process spawning from a web app) is itself the finding — see §6 |
| API integration | 7 | Consistent, simple JSON responses |
| DB integrity | N/A | Not applicable |
| Auditability | 8 | Correctly attributed logging (post-fix) |
| Reliability | 7 | Defensive process cleanup, daemon threads |
| Performance | N/A | Not applicable |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Not applicable |

**Overall status: NOT READY (for production deployment specifically — this module is fine for its intended development/demo use)**

This is a competently-built developer convenience feature, not a defective one — every specific piece of code found here is reasonable for its evident purpose. The finding is architectural: this module's entire category of capability (a web-reachable, admin-triggerable OS process launcher) should not ship into a production deployment of a system managing real organizational assets, no matter how tightly the current single use case is locked down. This is a deployment/packaging decision as much as a code fix, and should be explicitly resolved (confirmed excluded from production, or formally accepted as an intentional, documented exception) before this system goes live.
