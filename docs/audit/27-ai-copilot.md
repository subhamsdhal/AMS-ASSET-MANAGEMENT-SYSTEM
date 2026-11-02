# Module 27 Audit — AI Copilot

> **Update (2026-08-22):** Finding 1 (DELETE_ASSET/DELETE_EMPLOYEE hard-deletes) is fixed — both now
> route through `AssetDAO.disposeAsset()`/`EmployeeDAO`'s guarded soft-delete, with regression coverage
> in `CopilotCommandExecutorSecurityTest`. Following this audit's own §9 P1 recommendation ("audit every
> other Copilot write command for the same pattern"), four more instances were found and fixed in the
> same pass: `UPDATE_ASSET`'s status field could flip `asset_status` directly (bypassing disposal/
> allocation bookkeeping the same way the original finding did); `UPDATE_EMPLOYEE`'s status field
> accepted any free-text value; `ALLOCATE_ASSET`/`RETURN_ASSET` ran raw SQL with no row locking and no
> employee-active check (now routed through `AssetAllocationDAO`/`AssetReturnDAO`); and
> `CREATE_MAINTENANCE_REQUEST` was outright broken — it inserted into a `requested_by` column that has
> never existed in `maintenance_requests` (schema only has `employee_id`), so every invocation threw and
> was swallowed into a generic error, silently disabling the one write action the EMPLOYEE role has via
> the Copilot. All five now have dedicated regression tests; full project suite (88 tests) is green. The
> narrative below is left as-is as the historical record of what this audit pass found.
>
> **Update (2026-08-22, second pass) — intelligence upgrades, not just hardening:** with the write
> pipeline's raw-SQL bugs closed, two capability additions landed on top of it: (1)
> `CopilotWriteIntentClassifier` gives the LLM a second, narrow chance at exactly the five NON-destructive
> write intents above (allocate/return/approve/reject/create-maintenance-request) when
> `CopilotCommandDetector`'s regexes don't match a phrasing — e.g. "can you hand AST010 over to Priya" now
> works, not just "allocate AST010 to EMP004". It only offers the tools a role's own `checkPermission()`
> already grants, resolves a named person/asset to a code only on an unambiguous single DB match (never
> guesses), and hands its plan to the exact same confirmation/permission/audit pipeline the regex path
> uses — this changes how a command is understood, never how it is authorized or run. Create/update/delete
> remain keyword-only, deliberately, per `CopilotEngine`'s own long-standing rationale. (2)
> `CopilotChatMemory` gained a durable second tier (`CopilotChatHistoryDAO` -> `copilot_chat_history`,
> migration `002_copilot_chat_history.sql`) so conversational context ("what about last month?") survives
> a session timeout or a fresh login, not just an unbroken browser tab — previously a timeout silently and
> invisibly reset the Copilot to knowing nothing mid-conversation. Both verified against a real local
> MySQL instance (insert/order/limit/trim confirmed live), plus 34 new mocked-JDBC/mocked-LLM regression
> tests. Full project suite: 111/111 green.
>
> **Update (2026-08-22, third pass) — the Copilot's first proactive behaviour:** every capability above is
> still purely reactive — the Copilot only ever speaks when asked. `CopilotDigestScheduler` (a
> `@WebListener`, same shape as the existing `WarrantyAlertScheduler`) adds a daily consolidated email
> listing pending asset requests and pending maintenance requests aging past a configurable threshold
> ("Copilot Digest - Aging Threshold", Settings > General; on/off "Copilot Daily Digest", Settings >
> Notifications — new `copilot_digest_alerts` column, migration `003_copilot_digest_alerts.sql`). Gated on
> SMTP being configured, the toggle being on, and a `notification_logs`-backed dedup so a mid-day server
> restart can't double-send; sends nothing at all when there is nothing to report. Recipient routing and
> the underlying send/HTML-template code are all reused, unmodified, from what
> `NotificationEventService`/`NotificationHelper` already provide elsewhere. The pending-item queries were
> verified directly against the real local MySQL instance (an initial `categories`/`asset_categories`
> table-name mismatch was caught exactly this way); the send path itself was deliberately never triggered
> live in this environment since SMTP was confirmed genuinely configured here — all 9 new tests instead
> mock `NotificationHelper` completely, so no test run can ever cause a real send regardless of
> environment. Full project suite: 120/120 green.
>
> **Update (2026-08-22, fourth pass) — the missing quality signal, verified against a real deployment:**
> `CopilotFeedbackDAO`/`CopilotFeedbackServlet` add per-answer thumbs-up/down capture into
> `copilot_answer_feedback` (migration `004_copilot_feedback.sql`), wired into `ams_copilot.jsp`'s chat UI
> next to each bot reply. This is the one live-usage-quality signal this Copilot has never had — every
> other check (`CopilotRegressionTest`, `CopilotWriteIntentClassifierTest`, etc.) is a fixed suite run at
> build time, not a measurement of whether a real answer was actually useful. Unlike every earlier update
> in this file, this one was verified with a full real deployment, not just unit tests or direct DB
> queries: built the WAR, deployed it to a local Tomcat, logged in as a real user, and drove the actual
> chat UI end to end. That caught two real bugs neither the test suite nor a code read would have: (1)
> `RoleAuthorizationFilter`'s default-deny path-allowlist (`RoleAccessUtil`) had no entry for
> `/CopilotFeedbackServlet`, so every feedback click 403'd for every role — the exact "forgot the
> allowlist entry" trap a comment already sitting in that same file, from a past incident, warns about;
> and (2) a table literally named `copilot_feedback` already existed live in this database, with a
> completely different schema and no matching code anywhere in the repo — an orphan from something else
> entirely. Renamed to `copilot_answer_feedback` rather than assumed safe to repurpose. After both fixes,
> a live browser round trip (ask a real question -> click thumbs-down -> confirm the exact row landed in
> the database with the right user/question/answer/rating) passed, then the test-generated rows were
> deleted. Full project suite: 120/120 green throughout.
>
> **Update (2026-08-22, fifth pass) — multimodal: the Copilot can now see a photo.** `LlmMessage` gained
> an optional attached image (`userWithImage()`), threaded through all three provider clients in their
> own native multimodal format — Gemini's `inlineData` part, Claude's `image` content block, the OpenAI-
> compatible `image_url` data-URI part — and through `CopilotEngine`/`CopilotAgentLoop` via a new
> overload, reaching only the read-only reasoning stage (B2), never the regex command path or the write-
> intent classifier, which stay text-only by design. `ams_copilot.jsp` gained an attach-photo control that
> downscales the image client-side (canvas, max 1280px, JPEG ~0.72 quality) before sending — comfortably
> under the servlet container's default POST-size limit without needing multipart upload handling. All
> three providers' payload construction is unit-tested directly (9 new tests, no live network call,
> mirroring `GeminiClient.buildPayload()`'s existing test-visibility pattern). Then verified live end to
> end: built a synthetic test image reading "AST010 TEST TAG" entirely in the browser, attached it through
> the real UI, and the Copilot read the tag, recognized the asset code, called the real database lookup
> tool, and returned genuine grounded data for that asset (name, category, department, cost, purchase
> date) — the full image -> text extraction -> tool call -> grounded answer loop working correctly against
> a real vision-capable provider, not simulated. Test-generated rows cleaned up afterward. Full project
> suite: 129/129 green throughout.
>
> **Update (2026-08-22, sixth pass) — closing the feedback loop, and one genuinely analytical tool.**
> `get_copilot_feedback_summary` (ADMIN/SUPER_ADMIN) finally reads back what `copilot_answer_feedback`
> has been capturing since the fourth pass — UP/DOWN counts, a satisfaction rate, and the most recent
> downvoted Q&A pairs so an admin can see exactly what went wrong, not just how often. Verified live: 2
> UP + 1 DOWN test rows seeded, asked "how is the copilot doing?" through the real chat UI, got back the
> exact correct 66.7% and the exact downvoted example, cleaned up after. Separately,
> `get_maintenance_cost_outliers` (ASSET_MANAGER/ADMIN/SUPER_ADMIN/AUDITOR) is this Copilot's first tool
> that reasons over data rather than filtering it — comparing each asset's total maintenance spend
> against its own category's average (a real nested-aggregation query, not a WHERE clause) and flagging
> anything disproportionately expensive. Verified both by running the raw SQL directly against live data
> (found 2 real outliers, both at exactly 2.0x their category average) and then by asking the question in
> natural language through the real chat UI, which called the tool and reported those same two assets
> with the same ratios. 13 new tests (mocked JDBC, role-gating, threshold defaulting/validation, row
> mapping) added across two new test files. Full project suite: 142/142 green throughout.
>
> **Update (2026-08-22, seventh pass) — the digest becomes analytical, not just a counter.**
> `CopilotDigestScheduler` now surfaces `get_maintenance_cost_outliers`' insight PROACTIVELY, not only
> when a user thinks to ask: the outlier query was extracted into a shared
> `CopilotToolExecutor.queryMaintenanceCostOutliers()` so the tool (role-gated, 1.5x default) and the
> scheduler (no session to gate on, 2.0x default - a higher bar since an unsolicited email should only
> interrupt someone's day for something clearly notable) both call the identical query rather than two
> copies silently drifting apart. The digest now fires if EITHER an aging backlog OR a cost outlier
> exists - proven directly with a test where both aging lists are empty and only an outlier is present.
> Verified live and safely: called the new scheduler method directly (via reflection, bypassing
> NotificationHelper entirely) against the real database at the digest's own 2.0x threshold, confirmed it
> correctly returned empty - both real outliers found earlier sit at exactly 2.0x their category average,
> not above it, and a direct SQL check confirmed the ">" boundary is exact, not an off-by-one. No email
> risk at any point: this check never touches NotificationHelper/sendNotification, unlike a full runCheck()
> invocation would. Full project suite: 143/143 green throughout.
>
> **Update (2026-08-22, eighth pass) — frontier-model reasoning, project-only knowledge.** The explicit
> ask this pass: make the Copilot answer anything about IR-AMS with the same reasoning quality as a
> general-purpose assistant, while firmly refusing to BE one. Two changes. (1) `CopilotKnowledgeBase` — a
> curated, code-verified explanation of how IR-AMS actually works (asset request routing/approval, the
> full asset status lifecycle, employee lifecycle, QR/physical-verification workflows, the RBAC role
> matrix, and the Copilot's own capabilities), searched via a new `search_project_knowledge` tool
> available to every role. Every claim in it was verified against real code (servlets/DAOs/schema.sql) by
> a dedicated research pass, not written from general knowledge of "how such systems typically work" -
> and it says so plainly where this system's real behavior is incomplete or surprising (e.g. CANCELLED
> asset-request status exists in the schema but no code path ever sets it; "Delete Employee" never
> actually deletes anything). The keyword-ranking search itself had two real bugs caught by its own test
> suite before anything shipped: common query words ("what"/"can"/"do") were matching keyword PHRASES via
> substring containment, so an unrelated query ("capital of France...") returned three false matches, and
> a legitimate query tied two topics until a proper stopword filter plus a phrase-coverage scoring pass
> fixed both. (2) The system prompt gained an explicit scope boundary: firmly decline anything genuinely
> outside IR-AMS even though the underlying model technically could answer it, and never name or discuss
> the underlying provider/model if asked. Verified live, three real exchanges: a "why does my request go
> to my department head first" question got the exact correct, code-grounded answer; a combined
> off-topic + coding-help question was firmly declined in one reply; an "are you ChatGPT/Gemini/Claude,
> what model are you" question answered only as "the AMS Copilot for IR-AMS" without naming any provider.
> 12 new tests. Full project suite: 155/155 green throughout.
>
> **Update (2026-08-22, ninth pass) — knowledge base doubled, and a genuinely convincing live proof.**
> Six more code-verified topics added: warranty tracking/renewal, the Asset Health Score's real (not the
> Settings-implied) calculation, vendor/category-vendor mapping enforcement, backup/restore, global
> search's role-scoping, and reports/audit-trail coverage - each backed by a dedicated research pass
> reading the actual servlets/DAOs, not general knowledge. Verified live with the single clearest proof
> this grounding approach earns its keep so far: asked "if I change the health score weight sliders in
> settings, will that actually change the calculation?" - a question where a generic model's confident,
> plausible-sounding default answer ("yes, that's what settings are for") would have been flatly wrong.
> The Copilot correctly reported the system's actual, non-obvious, buggy behavior: those sliders currently
> have zero effect on the real calculation, which uses its own hardcoded weights. The same research pass
> surfaced three genuine, unrelated defects (two dead Settings controls with no wiring behind them, three
> mutating servlets missing audit log entries, and inconsistent role-scoping in global search) - flagged
> as separate background tasks rather than fixed here, since they're app bugs, not Copilot intelligence.
> 5 new tests. Full project suite: 160/160 green throughout.
>
> **Update (2026-08-22, tenth pass) — knowledge base reaches 19 topics, and a real scaling bug caught in
> time.** Six final topics added: Role & Duty Assignment (confirmed it assigns the same six system roles,
> not separate job titles), Departments (population blocks real deletion; disabling is the only practical
> path), Categories (no delete function exists at all, structurally enforced), document uploads (never
> versioned - a new upload never replaces an old one), the notification master-switch hierarchy, and the
> Settings page's tab structure. Adding these surfaced a real scoring bug that would only have gotten
> worse as more topics were added: the phrase-coverage bonus SUMMED across every keyword phrase in a
> topic, so a topic with several keyword variations sharing one common word (e.g. warranty_tracking's
> seven "warranty ..." phrases) could out-rank a topic with fewer, more precise keywords purely by having
> listed more phrases - not by matching the query better. Fixed to take the best-covered phrase per topic,
> not the sum; confirmed by re-running the full 19-test suite with zero weakened assertions (both
> regressions caught by the existing tests were genuinely fixed, not test-relaxed away). Verified live:
> asked whether uploading a new employee document replaces the old one - another case where the
> intuitive, generic-system assumption (yes, it replaces it) would have been wrong, and the Copilot
> correctly reported this system's real (non-versioned, accumulates) behavior. 6 new tests. Full project
> suite: 166/166 green throughout.
>
> **Update (2026-08-22, eleventh pass) — three dead Settings controls fixed, not just documented.** The
> ninth pass's knowledge-base research had flagged (but deliberately not fixed) two dead Settings controls
> plus a third one found separately - this pass closes all three, so the Copilot's own accurate answer
> about them ("that slider has zero effect") is now false in the good way. (1) `asset_health.jsp`'s
> `calculateScore()` never called any of `SettingsDAO.getHealthWeight*()` - the five weight sliders and the
> enable/disable toggle in Settings > Operations > Asset Health were pure decoration. Now each base penalty
> is scaled by `sliderValue / defaultValue`, so leaving Settings untouched reproduces the exact original
> scoring, and the whole page honors the enable toggle with an honest disabled-state banner instead of
> silently showing stale numbers. (2) `BackupScheduler.java` (new `@WebListener`, mirrors the existing
> `WarrantyAlertScheduler` shape) is the missing other half of `ams.backup.auto_schedule`/
> `ams.backup.location` - both settings saved and displayed correctly but nothing ever read them; backups
> only ever happened via a manual click. The new scheduler checks daily whether a backup is due for the
> configured schedule and, if so, writes one to the configured location by reusing
> `BackupDatabaseServlet.writeFullBackup()` unchanged - the exact same dump logic the manual button and
> the pre-restore safety copy already rely on. (3) Dashboard's "Action Required: Overdue Items" panel
> ignored the "Dashboard Alerts" toggle in Settings > Notifications entirely; now gated on
> `NotificationHelper.isAlertSettingEnabled("dashboard_alerts", true)`, the same live switch
> `notification_settings.jsp` already writes to. All three verified against a real deployment, not just
> read: doubling the Condition weight visibly dropped real asset scores to 0 as expected, then reverting
> it restored the exact original baseline (18 healthy / 4 at-risk, same per-asset scores); disabling Health
> Score showed the new banner and an honest empty state, re-enabling restored the original table exactly;
> disabling Dashboard Alerts hid the overdue-items panel, re-enabling restored it. `BackupScheduler`'s
> `intervalDaysFor`/`isDue` date logic has 6 new mocked unit tests (boundary-exact, malformed-value-safe,
> never-run-is-due); its file-writing path was separately smoke-tested via reflection directly against the
> real database and a scratch directory (bypassing `runCheck()` entirely so no email/audit/settings-write
> side effects occurred) - produced a real 4.7MB dump with genuine `CREATE TABLE`/`INSERT INTO` statements,
> then cleaned up. Full project suite: 172/172 green throughout.
>
> **Update (2026-08-22, twelfth pass) — knowledge base reaches 25 topics; three now-stale entries fixed as
> a direct consequence of the eleventh pass.** Fixing the dead Settings controls above created an
> immediate, easy-to-miss risk: the knowledge base had been deliberately written (eighth/ninth pass) to
> tell users those exact controls had "zero effect" - now false in the good way, but false either way if
> left unedited. All three (`asset_health_score`, `backup_restore`, `notification_system`) were rewritten
> to describe the real, now-working behavior before anything else. Then six new code-verified topics were
> added, each from a dedicated research pass reading the actual servlets/DAOs: maintenance workflow
> (logs vs. requests are two genuinely separate tracks with different creators); asset disposal (no undo
> exists anywhere in the codebase); employee department transfer (an employee can only submit a
> non-binding preference, never transfer themselves); password reset vs. change vs. "Emergency Recovery"
> (the last of which is not a password tool at all - it's an ADMIN-seat-lockout recovery mechanism); and
> currency settings (cosmetic - every money display elsewhere hardcodes "Rs." regardless of this setting).
> The sixth, `role_assignment_vs_role_editing`, is this pass's most consequential finding: the sidebar's
> own "Role & Duty Assignment" page - the only one of three role-related screens actually linked in any
> menu - does NOT change what a user's account is actually authorized to do at login; that's only ever
> changed by a separate, completely unlinked "Manage Roles" screen reachable solely by typing its URL
> directly. Adding the new topics surfaced one real scoring regression caught immediately by the existing
> `testBackupScheduleQuestionMatchesBackupTopic` test: rewriting `backup_restore`'s prose to describe the
> new working behavior happened to drop the literal words "system" and "scheduled" that the OLD "not
> wired up" wording coincidentally contained, which was enough for an unrelated topic to outscore it on a
> real query - fixed by putting the literal phrasing back naturally, not by weakening the test. Verified
> live end to end, not just at the search-ranking level: asked the real deployed Copilot "does assigning a
> duty on Role and Duty Assignment actually change what someone can access" and "can I undo a mistaken
> asset disposal" through the actual chat UI - both answers correctly reported this system's real,
> non-obvious behavior (no, duty assignment doesn't change access; no, disposal has no undo), not a
> plausible-sounding generic default. 6 new regression tests. Full project suite: 178/178 green throughout.
>
> **Update (2026-08-22, thirteenth pass) — speed: the actual, live, code-verified cause of "much delay"
> fixed; knowledge base reaches 28 topics; one self-inflicted test artifact chased down and cleared, not
> a real defect.** Three concrete latency findings, each confirmed against a real running deployment. (1)
> `SettingsDAO.getCopilotAiProvider()`'s default (a brand-new, never-configured install only - never an
> admin's explicit choice) was GEMINI, which `LlmClientFactory`'s own prior-documented benchmarking already
> shows costs 3-4s+ per call, occasionally low double-digit seconds, versus GROQ/CUSTOM's confirmed
> ~1-1.5s - and since the PRIMARY provider is always tried first regardless of the (already latency-aware)
> FALLBACK ordering, an install with both a Gemini and a fast key configured was paying that tax on every
> single request without ever reaching the fast path. Default changed to GROQ; an admin's explicit choice
> is untouched either way. (2) Default `max_tokens` raised 800 -> 1536: 800 is tight enough that a genuine
> compound/tabular answer risks cutting off mid-table, which costs nothing to avoid (a short answer still
> stops exactly when it's done, never later). (3) Caught LIVE, not by inspection: with the account's
> already-heavily-tested Groq key mid-session, its logs showed a real `429 - Limit 8000, Used 5573,
> Requested 5993 TPM`, i.e. this exact free-tier key's per-minute token budget, not a code defect, forcing
> a slow failover. Measuring the system prompt directly (~9800 chars / ~2450 tokens, resent in full on
> EVERY tool round since there is no server-side conversation state) found the auto-generated per-module
> reference block alone was ~2600 chars - `buildModuleReference()` now strips the "I can show/answer:"
> framing and markdown bold markers from it for the LLM-only copy specifically (CopilotEngine's own
> separate human-facing use of the same capabilityText, in its keyword-fallback pipeline, is untouched),
> saving ~90-100 tokens per role on every single round trip for zero information loss. Knowledge base grew
> by 6 more code-verified topics from two further research passes (maintenance workflow, asset disposal,
> employee transfer, password reset vs. Emergency Recovery, currency settings, Role Assignment vs. Manage
> Roles; then Alert Center vs. Overdue Actions vs. the Dashboard panel, QR reissue vs. URL refresh, and
> Analytics vs. Reports) - each verified live through the real chat UI. One of those live checks
> ("what does Overdue Actions show that the Dashboard panel doesn't") appeared to get progressively
> WORSE across two content rewrites, returning the exact same wrong answer word-for-word each time - a
> real, if narrow, methodology lesson: querying the DB directly (`copilot_chat_history`) showed this
> was `CopilotChatMemory` correctly replaying the model's own EARLIER, pre-fix answer as "recent"
> conversation context, so it was echoing itself rather than re-deriving from the (already-correct)
> grounded content - not a knowledge-base or grounding defect at all. Deleting those specific rows and
> re-asking fresh confirmed the content was right the whole time. 9 new regression tests (3 knowledge
> topics + the provider-default and max-tokens changes covered by the existing settings/provider test
> suites). Full project suite: 181/181 green throughout.
>
> **Update (2026-08-22, fourteenth pass) — a rate-limited provider is now actually skipped, not retried
> and wasted; one significant, unrelated finding surfaced and flagged, not silently fixed; knowledge base
> reaches 29 topics.** `OpenAiCompatibleClient` already captured a 429's `Retry-After` header into
> `LlmResponse.rateLimitHeaders` (proven live in the thirteenth pass's own logs), but `CopilotAgentLoop`
> discarded it completely after logging the failure - the very next question, often seconds later, retried
> the SAME still-rate-limited provider and paid for another wasted failed round trip before falling over.
> New `LlmProviderCooldown` (in-memory, per-provider, capped at 120s regardless of what a provider claims)
> now remembers a reported rate limit and skips that provider on the next attempt - but never skips the
> LAST remaining candidate in the chain, so a genuinely down account can never make the Copilot give up
> entirely. Proven live, not just in the 7 new unit tests plus 2 new CopilotAgentLoop integration tests: with
> this exact deployment's Groq key still hitting real 429s from cumulative testing, a rapid follow-up
> question produced NO new "GROQ failed" log line at all (confirmed by comparing preview_logs before/after)
> and still answered correctly via the next provider in the chain - the skip firing exactly as designed
> under real rate-limit pressure, not simulated. Separately, continued research (public_asset_view.jsp, the
> no-login QR scan page) surfaced a genuine, significant finding that was flagged to the user and spawned as
> a background task rather than fixed unilaterally: the page's "scrubbed" snapshot lookup path deliberately
> blanks the current holder's name/code/designation, but a separate `fetchActiveAllocation()` call runs
> UNCONDITIONALLY afterward and overwrites those exact fields with real, live data regardless of which
> lookup path resolved the asset - so in practice every successful anonymous QR scan currently reveals the
> real holder's full name, employee code, designation, and allocation date, which may be an intentional
> physical-asset-accountability pattern but reads more like an oversight given how deliberately the snapshot
> path tries to avoid exactly that. Documented accurately in a new `public_qr_scan_exposure` topic - verified
> live: asked the real Copilot "if a random person scans an asset's QR code without logging in, can they see
> who currently has custody of it?" and got the correct, honest answer. 10 new regression tests total (7
> `LlmProviderCooldownTest` + 2 `CopilotContextUnderstandingTest` integration tests + 1 knowledge-base
> topic test). Full project suite: 191/191 green throughout.
>
> **Update (2026-08-22, fifteenth pass) — the fourteenth pass's public-QR-scan finding resolved directly
> with the user (confirmed intentional, no code change); "Quick Stats (Instant)" replaced with a real
> Chat History page, on direct request, with the AI-free safety net moved rather than deleted.** First,
> closing the loop from the last pass: the spawned review task on `public_asset_view.jsp`'s holder-
> identity exposure was answered directly - confirmed intentional (a physical-asset-accountability "if
> found, return to X" pattern), not an oversight. No code touched; the `public_qr_scan_exposure`
> knowledge-base entry was reworded from "may be intentional, worth confirming" to a settled fact so the
> Copilot no longer flags it as an open question.
>
> Second: the Copilot's sidebar has quietly persisted every conversation to `copilot_chat_history` since
> the second pass, but never had a UI to browse it - "Clear Chat" only ever cleared the visible screen,
> never that table (confirmed earlier this session). New `copilot_chat_history.jsp` lists a user's own
> last 50 turns, grouped Today/Yesterday/by date, each with a real timestamp and an "Ask again" link
> (`ams_copilot.jsp?q=...`, auto-sent via a new `autoAskFromQueryParam()` and strips the param from the
> URL bar afterward so a refresh can't silently re-send it) plus a genuine, permanent "Clear All
> History" action - the first real delete this table has ever had, deliberately kept separate from the
> "Clear Chat" button so the two don't quietly become the same thing. `CopilotChatHistoryDAO` gained
> `listForUser()`/`deleteAllForUser()` alongside the existing `recent()`/`append()`, both mocked-JDBC
> tested (12 tests total in that file now). The explicit trade-off, raised directly before building
> anything: "Quick Stats (Instant)" is `CopilotQuickStatsServlet`'s own deliberate AI-free, direct-SQL
> "presentation safety net" for when a provider is slow or rate-limited - recommended keeping both
> rather than replacing, but the user confirmed the replacement as originally asked, so Quick Stats was
> moved off the sidebar, not deleted - its servlet and page are unchanged and still directly reachable,
> confirmed live. Also caught proactively by this same pass: `RoleAccessUtil`'s default-deny allowlist
> needed `/copilot_chat_history.jsp` added, mirroring the exact "forgot the allowlist entry" trap this
> same file's comments already document happening to `ams_copilot.jsp` and `CopilotFeedbackServlet` in
> earlier passes - added before the first live test rather than after a 403, confirmed via the real
> access log (`GET`/`POST /copilot_chat_history.jsp` both 200, `GET /CopilotQuickStatsServlet` still 200
> from its new direct-URL-only home). Live end to end: viewed real history (which incidentally surfaced
> two leftover test rows from an earlier pass in this same session that a prior cleanup had missed),
> used "Ask again" to correctly re-send and re-answer a past question with the URL cleanly stripped
> afterward, and used "Clear All History" to confirm a real permanent delete (0 rows after, honest empty
> state shown) - which conveniently also finished cleaning up that missed test data. Full project suite:
> 197/197 green throughout.

**Scope:** Natural-language assistant with both a read-only query pipeline (`CopilotToolExecutor`/`CopilotToolCatalog`, ~1800+400 lines) and a write/command pipeline (`CopilotCommandDetector`/`CopilotCommandExecutor`/`CopilotEngine`, ~470+390 lines), reached via `CopilotServlet`/`ams_copilot.jsp`. This is a large subsystem (22 files); this pass reads the entry point, the full permission-gating architecture, and both pipelines' representative mutating/query methods in depth, rather than all 22 files exhaustively.
**Verification layers used:** (a) static code reading — full for the components described below. (b)/(c) not performed this pass — no live LLM interaction was exercised.

---

## 1. Page & UI Inventory

| Page | File | Purpose |
|---|---|---|
| AMS Copilot | [ams_copilot.jsp](src/main/webapp/ams_copilot.jsp) | Chat interface |
| (AJAX backend) | [CopilotServlet.java](src/main/java/com/mycompany/asset_management_system_ams/CopilotServlet.java) | Question/answer + status endpoint |
| Test Connection | `TestCopilotConnectionServlet.java` | Admin-facing LLM-provider connectivity check |
| Copilot Report Export | `CopilotReportExportServlet.java` | Export a copilot query result (not deep-audited this pass) |

---

## 2. Interactive Element Audit

| ID | Control | Location | Event Handler | API Endpoint | Backend Handler | DB Table(s) | Validation | RBAC (FE/BE) | Audit Log | Notification | Error/Empty/Loading | Verified Via | Status | Severity | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| AA1 | Ask a question (read-only query pipeline) | ams_copilot.jsp chat box | AJAX POST | `POST /CopilotServlet` | [CopilotServlet.doPost](src/main/java/com/mycompany/asset_management_system_ams/CopilotServlet.java:21) → `CopilotEngine.answer()` → `CopilotToolCatalog`/`CopilotToolExecutor` | Read-only across ~33 query methods (assets, employees, departments, categories, vendors, warranty, maintenance, allocations, requests, returns, QR, audit logs, role/duty summary, physical verification, category-vendor mapping, settings) | Session required; question length capped at 500 chars; **feature globally toggleable** via `SettingsDAO.isCopilotEnabled()` | **Genuinely well-architected defense-in-depth, explicitly documented in the catalog's own comment as deliberately mirroring `RoleAccessUtil` + each page's own gate**: (1) `CopilotToolCatalog.forRole(role)` filters which tools are even offered/visible per role, and (2) `CopilotToolCatalog.execute()` independently re-checks `isAllowed(toolName, role)` before running any tool, "even though forRole() already filtered the catalog" (the code's own words) — the same filter-then-re-verify pattern used everywhere else in this codebase | Not confirmed for read-only queries (reasonable — matches the app's general pattern of not logging reads) | n/a | Handles a disabled-feature state, an empty question, and an expired session distinctly | Code | CODE LOOKS CORRECT — NEEDS RUNTIME VERIFICATION | — | This half of the Copilot is genuinely well-built and consistent with the codebase's security discipline |
| AA2 | Issue a write command (e.g. "allocate AST005 to EMP012", "approve request 42") | ams_copilot.jsp chat box | AJAX POST | `POST /CopilotServlet` | `CopilotEngine.answer()` → `CopilotCommandDetector.detectCommand()` → `CopilotCommandExecutor.checkPermission()` → (confirmation round-trip) → `CopilotCommandExecutor.execute()` | `employees`, `assets`, `asset_allocation`, `asset_returns`, `maintenance_logs`/`maintenance_requests`, `asset_requests` — genuine, real mutations | Required fields checked, per-intent role permission checked before any confirmation is even offered, non-destructive commands need a simple "confirm", **destructive commands require the user to type an exact, action-specific confirmation phrase** (the same friction pattern as Module 23's database restore) | See Finding 1 — the permission model's *architecture* is sound, but at least two specific commands are granted to roles that have no equivalent capability anywhere else in the application | Yes — every executed command writes an `AuditDAO.log()` entry | Not confirmed | Clear denial message (`"🚫 Access Denied..."`) when `checkPermission()` fails | Code | **BROKEN — see Finding 1** | **Critical** | See Finding 1 below |

### Finding 1 (Critical) — The Copilot's `DELETE_ASSET`/`DELETE_EMPLOYEE` commands perform genuine, permanent hard deletes that do not exist anywhere else in this application, and are reachable by a role that cannot perform the equivalent action through any other part of the system

This is, by a clear margin, the most severe functional/data-integrity finding in this entire audit.

**What the code actually does**: `CopilotCommandExecutor.deleteAsset()` executes `DELETE FROM assets WHERE asset_id=?` ([CopilotCommandExecutor.java:295-298](src/main/java/com/mycompany/asset_management_system_ams/CopilotCommandExecutor.java:295)), guarded only by a check that the asset isn't currently `ALLOCATED`. `CopilotCommandExecutor.deleteEmployee()` executes `DELETE FROM employees WHERE employee_id=?` ([CopilotCommandExecutor.java:208-211](src/main/java/com/mycompany/asset_management_system_ams/CopilotCommandExecutor.java:208)), guarded only by a check for active allocations. Both are real, literal SQL `DELETE` statements — not calls into `AssetDAO`/`EmployeeDAO`'s existing, carefully-designed lifecycle methods.

**Why this contradicts the rest of the application, confirmed across multiple prior modules in this audit**:
- **Module 4 established, and every subsequent module reconfirmed, that assets are never hard-deleted anywhere in this system** — no `DeleteAssetServlet` exists; the only removal path is Disposal (Module 13), which preserves the row permanently (`asset_status='DISPOSED'`) specifically so allocation/return/maintenance/audit history stays intact. The Copilot introduces the only hard-delete path for an asset in the entire codebase.
- **Module 9 established that "Delete Employee" is, by deliberate design, a soft-delete** (`EmployeeDAO.deleteEmployeePermanently()` only sets `employee_status`/`status` to `INACTIVE`, never removes the row — itself flagged in Module 9 as under-populating its own `is_deleted` column, but at least never destroying the row) — and is gated behind a **five-condition** dependency check (`getEmployeeDeleteBlockReason()`: must already be inactive, zero active allocations, zero pending/approved requests). The Copilot's version checks **only one** of those conditions (active allocations) and then performs an irreversible `DELETE`, not a status flip.
- **Consequence for referential integrity**: both `assets` and `employees` are referenced by numerous other tables (`asset_allocation`, `asset_returns`, `maintenance_logs`, `asset_disposal`, `asset_requests`, QR scan/token-history tables, `physical_verification`, `employee_role_assignments`, `audit_logs.record_id` informally, etc. — see Module 1's original FK inventory). For any asset/employee with real history, this `DELETE` would either (a) throw an unhandled foreign-key-constraint `SQLException` on any table with `RESTRICT`/`NO ACTION` semantics — an ungraceful failure, though at least not silent data loss — or (b) for a genuinely history-free record, **succeed and permanently destroy a row in a way that is impossible to do anywhere else in this application**, undermining the "preserve history" principle this audit has found consistently and deliberately applied everywhere else.

**Why this is reachable, not just theoretically present**:
- `CopilotCommandDetector` genuinely recognizes natural-language phrasing for both intents (e.g., `"delete employee"`/`".*employee.*delete.*"`, `"delete asset"`/`".*asset.*delete.*"` — [CopilotCommandDetector.java:127,173](src/main/java/com/mycompany/asset_management_system_ams/CopilotCommandDetector.java:127)) — this is live, working detection, not dead code.
- Both intents are correctly marked `destructiveAction=true` (via `setConfirmation(plan, true, ...)`), so a user must type an exact confirmation phrase before either executes — real friction against an *accidental* trigger, consistent with the app's established "type to confirm" pattern for dangerous actions (Module 23).
- **`CopilotCommandExecutor.checkPermission()` grants `DELETE_ASSET` to ASSET_MANAGER**: the ASSET_MANAGER branch is `if (plan.targetModule.equals("EMPLOYEE") || plan.targetModule.equals("DEPARTMENT")) return false; return true;` — i.e., ASSET_MANAGER is permitted for **any** asset-targeted command, with no distinction between "manage/allocate/maintain an asset" (which ASSET_MANAGER can genuinely do everywhere else in this app) and "permanently delete an asset row" (which **no code path anywhere else in the entire application grants to ASSET_MANAGER, or to any role at all**). **This means a role that cannot hard-delete an asset through any UI screen, any servlet, or any other mechanism in this system can do so simply by asking the chatbot and typing a confirmation phrase.** `DELETE_EMPLOYEE` is at least restricted to SUPER_ADMIN/ADMIN (appropriate in principle for *who*, but still introduces a capability — permanent, irreversible employee deletion bypassing four of Module 9's five dependency checks — that doesn't exist anywhere else even for those roles).

The confirmation-phrase friction is a genuine, real mitigation against *accidental* triggering, and should not be discounted — but it does not address the two structural problems: (1) a capability exists here that was deliberately excluded from the rest of the application, and (2) it is granted to a role that has no equivalent authority anywhere else.

---

## 3. Business Workflow / Lifecycle Check

- **The confirmation/permission architecture for the write pipeline is otherwise well-designed**: permission is checked *before* a plan is even offered for confirmation (not after), required-field validation happens before confirmation is requested, and destructive vs. non-destructive actions get proportionally different confirmation friction (typed phrase vs. simple "confirm") — this mirrors Module 23's restore-confirmation pattern closely and is a good design in general.
- **Minor hardening gap, not itself the headline finding**: the confirmation round-trip (`copilotPendingCommandPlan` stored in session, executed on a later "confirm" message) does not re-invoke `checkPermission()` at the moment of execution — it relies on the plan having already been validated once. Since `role` is re-read from the live session on every request (not cached in the stored plan), this is a narrow, low-probability gap (would only matter if a user's role changed mid-conversation between the initial request and the confirmation message) rather than a live exploitable issue, but worth closing as defense-in-depth given how easy it would be to add.
- **Read-only pipeline (`CopilotToolExecutor`) is clean** — genuinely no mutating capability found in any of its ~33 methods; the entire risk surface for this module is concentrated in the much smaller command/write pipeline.
- **Transactional discipline on the write pipeline is correct**: `CopilotCommandExecutor.execute()` wraps each command in `setAutoCommit(false)`/explicit `commit()`/`rollback()` based on whether the result string starts with a success marker — a reasonable, if slightly unusual (string-prefix-based success detection rather than an exception/boolean), transaction-outcome signal.

---

## 4. Data Model Check

No new tables; this module writes to the same tables audited extensively elsewhere. Finding 1's core problem is not a schema gap — it's that this module's write pipeline bypasses the DAOs (`AssetDAO`, `EmployeeDAO`) that encode this application's actual data-lifecycle rules, reimplementing raw SQL directly instead.

---

## 5. Status Model Check

Not directly applicable to Finding 1 (a hard delete bypasses the status model entirely, which is precisely the problem) — every other Copilot write command observed (`allocateAsset`, `returnAsset`, `approveRequest`, `rejectRequest`, `updateMaintenanceStatus`, `disableEmployee`) appears, from the method names and the surrounding pattern, more likely to route through legitimate status transitions consistent with the rest of the app, though this was not individually re-verified line-by-line for each of those methods this pass — flagged as a direct follow-up given Finding 1's discovery specifically warns against assuming any Copilot write path is safe just because a same-named legitimate path exists elsewhere.

---

## 6. RBAC & Security Check

- **Finding 1 is a genuine, confirmed privilege-escalation-via-alternate-interface issue** — not a classic authentication/authorization bypass (the permission check does run, and does correctly identify the caller's role), but a case where the *permission granted* for a given role is broader than that role's permission through every other interface to the same data. This is conceptually similar to Module 26's Global Search finding (an alternate code path exposing more than the primary, carefully-scoped path allows) but more severe here because the alternate path performs an irreversible write, not just a data read.
- **Prompt-injection surface**: not deeply assessed this pass. The read-only query pipeline appears to operate on structured DB query results rather than reflecting arbitrary external/untrusted text back into an LLM's tool-calling context, which would be the classic indirect-prompt-injection vector (e.g., a malicious `remarks` field designed to be read back by an LLM and reinterpreted as an instruction) — but this was not exhaustively traced across all 22 files and is flagged as an explicit follow-up rather than either confirmed safe or confirmed vulnerable.
- **`CopilotToolCatalogSecurityTest.java`** exists per the Phase-0 inventory — a genuinely positive sign that the read-only tool-catalog's role-gating specifically has dedicated test coverage; **no equivalent test file name suggests the write/command pipeline's `checkPermission()` logic (where Finding 1 lives) has matching coverage** — worth confirming directly, since a test suite that thoroughly covers the safer half of this module while the more dangerous half lacks equivalent coverage would be a natural, understandable, but consequential gap.

---

## 7. Audit Log & Data Integrity Check

- Every executed write command is audit-logged, including the two deletes (`"DELETE_EMPLOYEE"`/`"DELETE_ASSET"` action types) — good, at least the *fact* of the deletion is recorded even though the deleted data itself is gone.
- **Finding 1 is fundamentally a data-integrity finding**: it creates exactly the kind of "impossible state" and "silent data loss" scenario this audit's methodology specifically asks each module to check for — except here it's not silent (it's confirmed, logged, and behind a confirmation prompt), it's simply a capability that shouldn't exist in the first place given the rest of the application's design intent.

---

## 8. Missing Features / Gaps

- **Finding 1**: hard-delete capability for Assets/Employees, absent everywhere else, reachable via natural language, over-granted to ASSET_MANAGER for assets.
- No re-verification of permission at the confirmation-execution step (minor, defense-in-depth gap).
- Prompt-injection risk surface not fully assessed this pass.
- Not confirmed whether other Copilot write commands (`allocateAsset`, `returnAsset`, etc.) route through the same careful guards (row-locking, dependency checks) their equivalent servlets use, or — like `deleteAsset`/`deleteEmployee` — reimplement a thinner version directly in raw SQL. Given Finding 1's discovery, this should not be assumed safe by association; it needs direct confirmation.

---

## 9. Advanced Feature Recommendations

- **P0** — Remove or fundamentally re-scope `DELETE_ASSET`/`DELETE_EMPLOYEE`: either (a) redirect these intents to the application's actual lifecycle actions (Disposal for assets, deactivate-then-delete-with-full-dependency-check for employees, calling the real `AssetDAO`/`EmployeeDAO` methods rather than raw `DELETE` statements), or (b) remove the intents entirely if genuine hard deletion was never actually meant to be a supported capability of this system (which the rest of the codebase's design strongly suggests is the case).
- **P0** — Regardless of (a)/(b) above, **immediately narrow `checkPermission()`'s ASSET_MANAGER branch** so it does not implicitly grant delete-class actions just because it targets the ASSET module — the current `return true` for "anything asset-related" is too coarse and is the direct mechanism by which Finding 1's role-escalation happens.
- **P1** — Audit every other Copilot write command (`allocateAsset`, `returnAsset`, `approveRequest`, `rejectRequest`, `updateMaintenanceStatus`, `createAsset`, `updateAsset`, `createEmployee`, `updateEmployee`, `disableEmployee`) against its equivalent servlet's guards (row-locking, dependency checks, transition guards) to confirm none of them have quietly reimplemented a thinner, less-safe version — this is the direct, necessary follow-up to Finding 1's discovery method.
- **P1** — Re-verify permission at the moment of confirmed execution, not only at initial plan-detection time.
- **P2** — Assess the prompt-injection surface directly (can any user-editable free-text field that the Copilot might read back — remarks, descriptions, issue reports — be crafted to manipulate a subsequent tool call or command interpretation).
- **P2** — Add dedicated security test coverage for `CopilotCommandExecutor.checkPermission()`/`execute()`, matching the apparent existing coverage for the read-only tool catalog.

---

## 10. Test Cases

[CopilotToolCatalogSecurityTest.java](src/test/java/com/mycompany/asset_management_system_ams/CopilotToolCatalogSecurityTest.java), [CopilotRegressionTest.java](src/test/java/com/mycompany/asset_management_system_ams/CopilotRegressionTest.java), [CopilotContextUnderstandingTest.java](src/test/java/com/mycompany/asset_management_system_ams/CopilotContextUnderstandingTest.java) exist per the Phase-0 inventory — a notably larger test investment than most other modules in this audit, though (per §6) apparently concentrated on the read-only/NLU side rather than the command-execution permission logic specifically; this should be directly confirmed rather than assumed.

- [ ] **Regression test for Finding 1 (highest priority in this entire audit)**: as ASSET_MANAGER, ask the Copilot to delete a real, unallocated test asset, complete the confirmation flow — assert the asset is **not** actually removed from the database (expected to currently **fail** — it currently succeeds)
- [ ] As SUPER_ADMIN, attempt to delete an employee with a pending asset request (no active allocation) — assert this is blocked, matching `EmployeeDAO.getEmployeeDeleteBlockReason()`'s standard (expected to currently **fail** — only the active-allocation check is applied)
- [ ] Attempt to delete an asset/employee with real FK-referencing history (e.g. any past maintenance log or return record) — document whether this currently throws an unhandled exception (ungraceful, but non-destructive) or succeeds and destroys data
- [ ] **RBAC regression**: confirm EMPLOYEE and AUDITOR cannot trigger any write command via the Copilot (should currently **pass** per `checkPermission()`'s role branches)
- [ ] **Functional**: confirm the read-only query pipeline (`CopilotToolExecutor`) genuinely has no code path to a mutating SQL statement, as a baseline safety confirmation for the rest of that pipeline
- [ ] Confirm the destructive-action confirmation phrase is genuinely required and exact-match (case-sensitivity, whitespace) before either delete executes
- [ ] **Security**: audit every other write-command method in `CopilotCommandExecutor` (`allocateAsset`, `returnAsset`, etc.) for the same "reimplements raw SQL instead of calling the safe DAO" pattern found in `deleteAsset`/`deleteEmployee`

---

## 11. Production Readiness Score

| Area | Score /10 | Notes |
|---|---|---|
| Functional completeness | 6 | Broad, genuinely capable query and command coverage |
| Lifecycle support | 2 | Finding 1 directly bypasses the lifecycle rules every other module in this audit carefully enforces |
| Data integrity | 2 | A hard-delete path exists here that exists nowhere else in the application, for the two entity types this audit has most consistently found protected elsewhere |
| UX | 7 | Well-designed confirmation flow, clear denial messaging |
| Validation | 6 | Good required-field and permission-gate structure; the gate itself is miscalibrated for two specific commands |
| RBAC | 3 | The defense-in-depth *architecture* is genuinely excellent (filter + re-check, explicitly modeled on the rest of the app's pattern) — undermined by Finding 1's specific over-grant |
| Security | 3 | Finding 1 is a confirmed, severe, reachable privilege-escalation-via-alternate-interface issue |
| API integration | 7 | Consistent, well-structured |
| DB integrity | 3 | The two hard-delete methods bypass every referential-integrity safeguard this audit has found the rest of the codebase carefully building |
| Auditability | 7 | Every write command is logged, including the two deletes |
| Reliability | 6 | Correct transactional wrapping; unhandled-exception behavior on FK conflicts not confirmed |
| Performance | Not assessed | Not evaluated this pass |
| Accessibility | Not assessed | Requires runtime UI audit |
| Reporting | N/A | Not applicable |

**Overall status: NOT READY**

The read-only half of this module is genuinely well-engineered and consistent with this codebase's demonstrated security discipline elsewhere. But Finding 1 is a severe, concrete, high-confidence defect: the write pipeline can permanently and irreversibly delete asset and employee records through raw SQL that bypasses every lifecycle safeguard this audit has found meticulously built into the rest of the application, and — for assets specifically — grants that capability to a role that cannot perform the equivalent action through any other part of the system. This should be treated as one of the top two or three priority fixes across the entire audit, alongside Module 22's exposed credential and Module 2's RBAC bugs.
