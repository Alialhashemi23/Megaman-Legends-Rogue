# Worker briefs: accounts, admin and Android

Prepared 2026-10-14 after the user answered the decision questionnaire. Features below are **not implemented**. Start from the merged `main` planning baseline; read root HANDOFF.md, DESIGN.md, [IMPLEMENTATION-DECISIONS.md](IMPLEMENTATION-DECISIONS.md) and the relevant sections of [ACCOUNTS-ANDROID-PLAN.md](ACCOUNTS-ANDROID-PLAN.md). Do not repeat pass-16 work or deploy the live service.

These are assignable briefs for the user's workers, not evidence that workers have been launched. The user controls assignment. Do not spawn agents, create other tasks or message other threads without the user's instruction. Use separate implementation branches/checkouts when working concurrently; no automatic destructive cleanup.

## Sequence and shared ownership

1. **A: backend/auth foundation** publishes the tested API/auth contract and fixtures first.
2. **B: game account sync** and **C: admin dashboard** depend on that contract. They can prepare UI/mock-based work before A finishes, but cannot declare integration complete against mocks.
3. **D: Android** can independently establish export/input/lifecycle support, then integrate A/B for account acceptance.
4. **E: co-op feedback** is independent of the backend contract, but overlaps B/D in Godot files. Sequence or coordinate those edits explicitly.
5. An **integration owner** verifies the combined build, refreshes packages and updates handoffs after the relevant work packages land. Do not merge stale generated bundles from concurrent branches.

Backend API/schema/identity ownership belongs to A; B owns game account/progress integration; C owns `/admin` and analytics views; D owns Android export/packaging/platform secure storage; E owns map/cache behavior. `scripts/game.gd`, `hud.gd`, `net.gd`, `settings.gd`, `server/server.js`, Compose and export presets are shared hotspots. Coordinate edits there rather than overwriting another worker's changes. New interfaces should be modules, not a monolithic rewrite.

## A. Backend, authentication, progress API and deployment files

**Prompt:** Implement the confirmed local-first Node + PostgreSQL + Better Auth backend. Preserve the current static host/WebSocket relay and guest compatibility. Build email/password signup, verification/recovery, secure browser sessions, first-party device-code login for Windows/Android, server-derived account identity, owner-role bootstrap, persistent schema migrations, transactional profile operations and tested backup/restore/deployment files. Use isolated containers/accounts/mail fixtures. Do not provision or deploy live services.

First deliverable is a short checked-in `docs/ACCOUNT-API.md` with actual request/response schemas, fixtures, error codes, session expiry/renewal, logout, run-lease/takeover/late-result semantics and browser/native examples. Prove device authorization and bearer session validation with a non-browser HTTP client before other workers rely on it. Document and pin supported Node/auth/database versions; the current Node service uses ESM and the Docker image uses Node 22. Do not add Express or TypeScript build tooling unless integration needs it and packaging remains reproducible.

Contract targets to settle in that document:

| Surface | Intended contract |
|---|---|
| `/api/auth/*`, `/account`, `/account/device` | Auth library handler plus same-origin account/device approval pages, with invite-safe return paths |
| `GET /api/v1/profile` | Verified account id, profile schema, server revision and confirmed progress; no secrets |
| `POST /api/v1/runs` and run heartbeat/takeover actions | Issue account-bound run id/lease and profile snapshot; reject concurrent starts without explicit takeover |
| `POST /api/v1/run-results` | Stable run/operation id and bounded outcome data; derive awards server-side, atomically finalize once and return the confirmed profile |
| `POST /api/v1/purchases` | Node/character, expected revision, operation id; atomic prerequisites/balance validation and spend |
| `POST /api/v1/discoveries` | Valid part ids with idempotent union; preserve discovery persistence without arbitrary profile replacement |
| `POST /api/v1/migrate-guest` | Preview/confirm token or equivalent bound confirmation; one-time validated adoption into an empty account |
| `POST /api/v1/lobby-ticket` | Short-lived single-use ticket; `/ws` resolves account identity from it, preserving distinct guest ids |
| `/api/v1/admin/*` | Read-only aggregates and paginated account detail, all authorized server-side; C implements views against this boundary |
| Error shape | Stable code + safe message + request id; distinguish unauthorized, unverified, forbidden, validation, revision conflict, active run, rate limit and retryable outage |

Route names other than the listed auth/metadata origins can change **once during A's contract spike**, with the final document/fixtures delivered to dependent work. After publication, version changes explicitly rather than silently breaking B/C/D. Authenticate the account from the session, never a request's owner field. Keep v2 profile migration, abandoned-dig semantics and the friends-co-op trust boundary explicit.

**Acceptance:** cross-account reads/writes and ordinary-user admin access denied; forged/expired/reused lobby tickets denied; guest reconnect retained; verification/reset/device approval expiry/replay/cancellation tested; double-submit and lost-response retries grant/spend once; conflicting operation bodies rejected; stale revision cannot overwrite; account deletion cannot replay old receipts; server/database restart and container replacement retain profiles; backup restores auth ids/profile/admin role into an isolated instance; real secrets/profile data absent from Git/builds. Publish synthetic event hooks/fixtures for C. Use appropriate backend and relay regression tests, not every unrelated Godot suite.

## B. Browser/Windows account experience and progress sync

**Prompt:** Integrate A's published API into the Godot/browser game. Add guest/sign-in/account status, account-scoped local caches and durable pending-result retries. Sync confirmed records/unlocks/Zenny/trees across browser/Windows, preserve existing local saves and save codes, and use verified server identity for co-op. Implement migration preview, online-only account starts/spending, explicit account takeover and clear failure/retry state. Native login opens the account device-approval flow and uses secure token storage; coordinate platform storage with D. Do not implement auth cryptography or bypass the backend with client-supplied balances.

Own the shared game progression hooks and account module. Keep device settings local. Handle purchases, discoveries, finished/abandoned runs and existing pending digs without duplicate progress. Login/logout/import remain blocked or safely deferred during a dig/lobby as required to avoid identity changes mid-session. Coordinate with A on session expiry and with E on pending upgrade queues. Preserve cobalt adventure menus, controller navigation, browser focus/clipboard behavior and the existing recovery mirror for non-secret guest progress.

**Acceptance:** browser -> second browser -> Windows confirmed progress matches; purchase/end-run saves survive reload/disconnect/lost response; failed sync never says saved; pending wallet cannot be spent; account switches cannot leak caches/results; guest progress survives login/logout and migration rejection; established cloud wallet cannot be overwritten by a save code; browser isolation headers do not break account return; co-op account rejoin/host migration preserves builds. Test against A's real local backend plus isolated profile paths, with targeted progression, browser and reconnect tests. Update tests for account/guest paths without changing personal saves.

## C. Read-only owner dashboard and analytics

**Prompt:** Build the confirmed read-only `/admin` dashboard using A's server-authorized admin role and event interfaces. Include user search/detail, registrations, login outcomes, distinct DAU/WAU/MAU, estimated foreground play duration, platform/version distribution, runs/wins/depth/character summaries and save-service failures. Use the exact definitions/retention in IMPLEMENTATION-DECISIONS.md. Add charts/tables with date filters, pagination, UTC labels, empty/error states and synthetic fixtures. A development/database administration console is not the requested game dashboard.

Coordinate server event collection with A and foreground activity signals with B/D. Count finalized run/result retries once, keep login/refresh distinct, and compute distinct-user windows from account/day data. Include the scheduled retention implementation and account-deletion handling. Mask emails in lists and exclude sensitive raw logs. No moderation, session impersonation, role editor, currency edits or reset-progress endpoints.

**Acceptance:** unauthenticated/ordinary users cannot fetch admin data even by direct API requests; owner can view it after role bootstrap/MFA; fixtures produce exact distinct-user counts across days and multiple devices; refreshes/replayed receipts do not inflate logins/runs; retention does not remove reward deduplication; logout removes access; dashboard never renders tokens/passwords/reset URLs. Check accessibility, layouts, paging and date boundaries. Do not claim historical stats before instrumentation existed.

## D. Retroid APK, secure storage, lifecycle and startup update check

**Prompt:** Add a reproducible native ARM64 Android export and package script for the pinned Godot engine, targeting Retroid Pocket 5 in landscape. Fix Android writable paths for progress, settings, audio, network identity and checkpoints while preserving Windows portable/browser behavior. Use existing controller actions, validate handheld menus/text entry, and handle sleep/background/Wi-Fi loss through the current reconnect/host-migration system. Implement A/B device login with Android secure credential storage and the boot-time update flow selected by the user: version metadata and opening the browser download page. No embedded WebView game or integrated APK installer.

Coordinate shared path helpers with B and controls with E. Exclude APK signing keys/passwords from tracked presets and packages; add the required ignore rules and environment-driven signing. Use `dev.galosengen.relicdiver`, increasing versionCode and a documented stable signing identity. Metadata lives at `/updates/android/stable.json`, with latest/minimum online version, game protocol, release notes, download page/APK URL, byte size and SHA-256. Ship metadata/download-serving configuration but do not publish files live. Keep first-run development/debug signing separate from real release signing.

**Acceptance:** signed test APK installs and upgrades in place; saves/settings/account access persist; no plaintext persistent token fallback; all four diggers and tree attacks work; actual Retroid + browser + Windows complete co-op with late join, choices, revive, lift, host migration both ways and suspend/rejoin. Measure a sustained full run for frame pacing/heat/battery and readable UI. Test metadata outage, no/optional/required update, browser-download cancellation and version rejection. Hardware access and owner release key are launch gates; emulator-only work is not complete Retroid validation.

## E. Already-requested co-op map/cache improvements

**Prompt:** Implement the three pending group-play requests in NEXT-FEATURES.md: party-shared map exploration/clear state, deferred notification when a teammate opens a cache, and chest/part-cache icons on the minimap. Use the engineering defaults in IMPLEMENTATION-DECISIONS.md (new rebindable C/RB pending-upgrades action). Preserve every player's independent reward eligibility and pending queues across reconnect/checkpoints. Keep solo choice behavior and existing controller actions.

**Acceptance:** multiple players reveal/clear different rooms and all maps converge, including late join/restore; a teammate opening a cache shows notification without stealing focus; each player opens/chooses each reward once at their convenience; queued choices survive reload and host migration; icons reflect visibility and personal availability/claimed state; rebinding has no conflict with Parts or other actions. Bump protocol/checkpoint version only if changed state requires it, update validation/message shapes, and run relevant UI/options/network/restore checks.

## Integration owner and completion report

Before merging an implementation package, review the API/identity contract, test its meaningful failure cases and ensure no personal saves, secrets, databases, dumps, caches or loose engine executables are staged. Preserve original asset/license exceptions. No worker deploys the live site, buys a service or publishes a release without the user's request.

After combined gameplay changes, export the Windows pack, refresh notices, run `tools/package-windows.ps1`, and rebuild `build/RelicDiver-Web.zip` with the existing web packager. Include Android packaging/metadata checks when D lands; do not claim an APK exists before producing it. Run relevant integration/browser/native tests once for the actual combined changes rather than blindly rerunning every suite per document edit. Document build/protocol/schema compatibility and tests actually run, including any unavailable hardware/deployment input.

Update HANDOFF.md, the affected subsystem handoff and the feature report with implemented scope versus outstanding launch gates. Keep these worker briefs as requirements; mark individual packages complete only with evidence. This planning merge changes documents only and therefore does not rebuild gameplay bundles or provision services.
