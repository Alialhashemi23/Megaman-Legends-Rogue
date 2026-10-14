# Roadmap: co-op polish, accounts, admin dashboard and Android

The single source of truth for the next features. It replaces the earlier NEXT-FEATURES, ACCOUNTS-ANDROID-PLAN, IMPLEMENTATION-DECISIONS and WORKER-BRIEFS documents (all 2026-10-14; see Git history for the originals). Product choices were finalized with the user on 2026-10-14; nothing below is implemented unless its status says so.

## Status

| # | Phase | Status | Depends on |
|---|---|---|---|
| 1 | [Co-op map and cache polish](#phase-1--co-op-map-and-cache-polish) | Done on `feature/coop-map-sharing` (protocol 7); awaiting merge and a group playtest | — |
| 2 | [Android development APK (guest + cross-play)](#phase-2--android-development-apk) | Build, saves, update-in-place, online connect and reconnect verified on the emulator; Retroid hardware and credits page outstanding. See [ANDROID.md](ANDROID.md) | — |
| 3 | [Backend: auth, profile API, deployment](#phase-3--backend-auth-profile-api-and-deployment) | Done (server only, off by default). Contract: [ACCOUNT-API.md](../ACCOUNT-API.md); operations: [ACCOUNTS-OPS.md](../ACCOUNTS-OPS.md). Admin MFA and the phase 6 event hooks are outstanding | — |
| 4 | [Game account sync (browser, Windows)](#phase-4--game-account-sync) | Implemented on `feature/account-sync` (`084d6a6`), pushed and deployed to the local server; awaiting merge. Live accounts backend still unconfigured. Storage/checks: [ACCOUNT-SYNC.md](ACCOUNT-SYNC.md) | 3 |
| 5 | [Android accounts and startup updates](#phase-5--android-accounts-and-startup-updates) | Not started | 2, 3, 4 |
| 6 | [Read-only owner dashboard](#phase-6--read-only-owner-dashboard) | Not started | 3 (+ activity signals from 4/5) |
| — | [Launch](#launch-owner-supplied-inputs) | Owner-run | Inputs below |

Update this table when a phase lands, with the merge commit and the tests actually run.

## Cadence

- **One phase at a time**, each on its own branch from `main` (e.g. `feature/coop-map-sharing`). Larger phases are split into the numbered steps below, one commit (or small group of commits) per step.
- **Each phase ends with:** the relevant checks for what changed (not every suite), refreshed `build/RelicDiver-Web.zip` / Windows pack only if gameplay changed, an updated HANDOFF.md + subsystem handoff + this status table, then merge to `main` once the user approves.
- **Deployment is the owner's.** Do not restart the live `relic-diver` container, provision services or publish releases/APKs unless asked. Redeploying drops online lobbies.
- **Order is a recommendation.** Phases 1 and 2 give playable results quickly (new co-op features; the game on the Retroid) before the long backend work. Phase 2 also centralizes save paths, which phase 4 builds on. The user can reorder.

## Confirmed decisions

| Decision | Selected |
|---|---|
| Backend | Existing Node server + PostgreSQL + Better Auth, Docker Compose, self-hosted. Supabase (managed or self-hosted) evaluated, not selected |
| Host | Owner's laptop (11th-gen i7, 16 GB, 512 GB SSD) on Ubuntu Server, later a VPS. Same hostname `megaman.galosengen.dev` and Cloudflare Tunnel |
| Login | Email + password with verification and recovery. Social and magic-link login deferred |
| Registration | Open; guest play remains |
| Offline | Account runs and purchases start online only; a run already started can finish offline and retries its save. Guest progress is separate and works offline |
| Admin | Read-only statistics and user inspection. No suspensions, impersonation, currency or progress editing |
| APK updates | Startup metadata check, then open the download page in the system browser. No integrated downloader/installer in v1 |
| Android app id | `dev.galosengen.relicdiver` (never change once a signed build is distributed) |
| Branch | Merge into `main`; no `master` |

No paid service without the owner's approval. There is no planned hosting subscription; electricity, domain, email delivery, off-host backups and eventual VPS/bandwidth may cost money.

## Rules for every phase

- **Preserve** the Legends look, run-reset rules, personal saves, Windows portable saves and the browser recovery mirror. Settings (controls, graphics, audio) stay device-local.
- **Don't rewrite the combat simulation** to add accounts. Add new modules rather than growing the monoliths. Shared hotspots: `scripts/game.gd`, `hud.gd`, `net.gd`, `settings.gd`, `server/server.js`, `docker-compose.yml`, `export_presets.cfg`.
- **Version numbers are independent:** game protocol `NET_VERSION` (`scripts/net.gd`, now 6), `CHECKPOINT_VERSION` (`scripts/game.gd`, now 3), profile `VERSION` (`scripts/progression.gd`, now 2), the `/api/v1` contract and Android `versionCode`. Bump only what a change affects. Incompatible clients get an update instruction before joining.
- **Trust model stays friends co-op.** Authentication, validation, rate limits and deduplication stop impersonation and accidental duplicates; they don't prove a reported run was earned honestly. No competitive leaderboards or server-authoritative combat in this work.
- **Never commit or package** `.env`, tunnel tokens, auth secrets, sessions, databases/dumps, personal profiles, keystores or signing passwords.
- **Tests use disposable accounts, isolated profile paths and a local mail sink.** Don't claim hardware, deployment or live-email checks that didn't happen.

---

## Phase 1 — Co-op map and cache polish

Requested by the user after group play.

1. **Shared map.** Merge revealed and cleared rooms across the party so every minimap shows the team's exploration. Share room state, not positions (teammate dots already exist). Cleared state is host-authoritative.
2. **Deferred cache choices.** When a teammate opens a cache online, show a notification instead of immediately opening the selection screen. Each player opens their pending choice when ready. Solo keeps today's immediate choice.
3. **Chest icons.** Distinct minimap icons for revealed chests/part caches, showing per-player available / pending / claimed state. Drawing an icon never consumes anyone's reward.

**Controls (user decision, 2026-10-14):** no new button. The existing **Buster parts** action (**Tab / Select**, "View" on Xbox pads) opens a waiting upgrade choice when there is one, and the parts screen otherwise. The choice screen also shows the digger's fitted parts, so checking the build and choosing an upgrade aren't exclusive. Prompts in the cache notification use that action's current binding.

**Where:** `world_state()` / `apply_world_state()` and the online section of `scripts/game.gd` (cleared/visited rooms, choices, `M_CLEARED`, `M_CHOICE`, `SHAPES`), `build_state()` queued choices, `map_at` in `scripts/hud.gd`, `scripts/settings.gd` `ACTIONS`.

**Done when:** players clearing different rooms converge to the same map, including late join and checkpoint restore; a teammate's cache shows a notification without stealing focus; each player claims each reward exactly once, and queued choices survive reload and host migration; icons respect visibility and per-player state; rebinding has no conflicts. Bump `NET_VERSION` / `CHECKPOINT_VERSION` only if the synced state changes. Checks: UI, options, `run_resume_checks.gd`, `server` tests, `tests/net_test.sh`.

---

## Phase 2 — Android development APK

Native Godot export for the Retroid Pocket 5 (Android 13, Snapdragon 865, 5.5" 1080p). No WebView wrapper. Guest play and cross-play co-op; accounts come in phase 5.

**Steps**

1. **Toolchain.** Install JDK and Android SDK versions that match Godot 4.7.1 (check its docs, not the newest SDK), plus the 4.7.1 Android export templates. Document setup in TECHNICAL.md.
2. **Writable paths.** Progress, settings, audio settings, `online.json` identity and checkpoints currently use `res://save/...` on non-web builds (`game.gd`, `settings.gd`, `sound.gd`, `net.gd`), which is read-only in an APK. Centralize them in one path helper: Android → `user://`, web unchanged (`user://`), Windows keeps its portable `save/` folders.
3. **Export preset and packaging.** ARM64, landscape, Compatibility renderer, 60 FPS target, Internet permission (HTTPS + WSS), app id `dev.galosengen.relicdiver`, increasing `versionCode`. A reproducible `tools/package-android.ps1`. Signing comes from environment variables, never tracked presets; add ignore rules for keystores. A debug/test key for development; the release key is a launch input. Ship engine and asset notices and an in-game credits/license view.
4. **Handheld UX.** Validate every menu with the real sticks, triggers, buttons and Back key across Retroid controller modes, including the Workshop, save codes and pending choices. Soft-keyboard text entry, legible text at 5.5", safe areas, docked display. Add render resolution/quality options only if measurements need them. Phone touch controls are out of scope.
5. **Lifecycle.** Sleep, backgrounding, Wi-Fi changes and process death go through the existing reconnect/host-migration path. A sleeping handheld can't keep hosting; a long sleep may outlast lobby retention and must say so.

**Progress (2026-10-14):** steps 1–3 and the lifecycle reconnect are done and emulator-verified (details and screenshots in [ANDROID.md](ANDROID.md)). Still open: step 4 on real hardware (controller mappings and prompts, text entry, readable text), the in-game credits/licence page, and the performance run on the Retroid.

**Done when:** a test-signed APK installs and upgrades in place without losing saves/settings; all four diggers and their tree abilities work; the Retroid + browser + Windows complete a co-op dig with late join, choices, revive, lift, host migration in both directions and suspend/rejoin; a sustained full run is measured for frame pacing, heat and battery. Emulator-only results don't count as Retroid validation.

---

## Phase 3 — Backend: auth, profile API and deployment

Extends the existing Node service (ESM, plain `http`, `ws`, Node 22 image). Keep the static host, COOP/COEP headers, lobby relay and guest compatibility. Pin Better Auth, the PostgreSQL driver and PostgreSQL versions; don't add Express or a TypeScript build unless integration needs it and packaging stays reproducible. Never invent password hashing or reset protocols.

**Steps**

1. **Spike + contract.** Prove Better Auth on the Node server against PostgreSQL, the device-authorization plugin and bearer sessions with a non-browser HTTP client. Publish `docs/ACCOUNT-API.md` with real request/response schemas, fixtures, error codes, session expiry/renewal, logout, run lease/takeover/late-result semantics, and browser + native examples. Route names may change once here; after publication, version changes explicitly. If a library piece doesn't work, report the incompatibility and an alternative before changing the stack or weakening token storage.
2. **Auth.** Email/password signup, verification + resend, sign-in/out, forgot/reset, session cleanup. Verified email required for account progression; unverified users play as guests. Replaceable mail adapter, local mail sink in development, reset tokens never logged.
   - **Browser:** same-origin account pages at `/account`, secure HttpOnly cookies, CSRF/origin checks, a safe return path that restores a pending lobby invite. Test under the game's COOP/COEP headers. Never put auth tokens in the progress mirror.
   - **Windows/Android:** Better Auth first-party device flow. The game shows a short code + URL (`/account/device`) and can open the system browser; the site signs in, shows the matching code and requires explicit approval; the game polls at the given interval. Cover cancellation, expiry, denial, slow-down and one-time redemption. QR code optional. No app links or loopback callbacks in v1. API calls use the bearer session.
3. **Profile data and API.** PostgreSQL with explicit migrations. Account subject → opaque game account id + display name (email stays in the auth tables). Versioned progress: records, discovered parts, earned/legacy unlocks, Zenny, tree nodes. A server revision (separate from the local `revision`), migration marker and an operation ledger keyed by account + operation id, including run receipts and purchases. The owner is always derived from the session, never a request field.

   | Endpoint | Contract |
   |---|---|
   | `/api/auth/*` | Better Auth handler |
   | `GET /api/v1/profile` | Account id, profile schema, server revision, confirmed progress; no secrets |
   | `POST /api/v1/runs` (+ heartbeat, takeover) | Issue an account-bound run id and lease; reject a concurrent start without explicit takeover |
   | `POST /api/v1/run-results` | Run/operation id + bounded outcome; server derives Zenny; finalize once; return the profile |
   | `POST /api/v1/purchases` | Node, character, expected revision, operation id; check prerequisites and balance; spend once |
   | `POST /api/v1/discoveries` | Idempotent union of valid part ids |
   | `POST /api/v1/migrate-guest` | Preview + bound confirmation; one-time adoption into an empty account |
   | `POST /api/v1/lobby-ticket` | Short-lived, single-use ticket for `/ws` |
   | `/api/v1/admin/*` | Read-only aggregates and paginated account detail (phase 6) |
   | Errors | Stable code + safe message + request id: unauthorized, unverified, forbidden, validation, revision conflict, active run, rate limited, retryable outage |

   **Sync rules:** the server profile is authoritative for signed-in players. Purchases are revision-checked transactions; on conflict, reload and ask the player to retry, never merge Zenny or compare device timestamps. Run results are idempotent per account + run id, and a repeated operation id with a different body is rejected. Deduplication outlives the retry window and account deletion can't replay old receipts. One active account run at a time; a second device takes over explicitly, and an expired lease never discards a valid pending result. Keep pass-16 legacy-unlock migration and abandoned-dig accounting without duplicate rewards.
4. **Co-op identity.** `/ws` accepts a lobby ticket, consumes it and derives an opaque account player id. `hello.id` is never proof of an account. Guest ids stay in a separate namespace and can't impersonate accounts. An account can rejoin a still-live lobby from another device (replacing the old connection safely). No credentials in invite URLs or logs. Durable lobbies across server restarts on another device stay out of scope.
5. **Admin role.** Assigned only by an operator command against an existing verified account id. No first-signup promotion, client-editable roles or hard-coded credentials. Enforced server-side on every admin endpoint. MFA required before the dashboard is public. Database and admin ports stay private.
6. **Deployment and operations.** Compose with a persistent PostgreSQL volume, health checks, restart policies, least-privilege credentials, env-var configuration, pinned versions and no automatic database major upgrades. Encrypted off-machine backups of database, auth data and config (initially 7 daily + 4 weekly) with a tested restore into an isolated instance; a Docker volume is not a backup. An operator checklist for the Ubuntu laptop and a later VPS move: rehearse a restore, verify accounts/roles, briefly stop writes, final backup/restore, switch the tunnel, validate writes, keep the old host read-only for rollback, never run two writable copies. No zero-downtime promise.

**Progress (2026-10-14):** steps 1–6 are implemented. The spike passed on Better Auth 1.7.7 + `pg` 8.23.1 + PostgreSQL 17.11; `server/test/accounts.test.js` (19 tests) covers the acceptance list below against a disposable database, and `server/test/rules.test.js` keeps the server's progression rules identical to the GDScript. The Compose stack (`docker-compose.accounts.yml`) was run end to end with real SMTP (Mailpit): container replacement and a database restart kept data, and an encrypted backup restored into an isolated instance with accounts, sessions, the admin role and the ledger intact. Decisions made during implementation: Better Auth's admin plugin is **not** used (it exposes ban/impersonate/set-role endpoints); the role is a non-input user field set only by `server/admin-role.js`. Device codes must be looked up by the signed-in website user before they can be approved, which binds them to that user. Still open: two-factor sign-in for the admin before the phase 6 dashboard is public, and the synthetic event fixtures for phase 6 (no analytics events are recorded yet).

**Done when:** cross-account reads/writes and ordinary-user admin access are denied; forged, expired and reused lobby tickets are denied while guest reconnects still work; verification, reset and device approval handle expiry, replay and cancellation; double-submits and lost responses grant/spend once; stale revisions can't overwrite; database restart and container replacement keep profiles; a backup restores auth ids, profiles and the admin role into an isolated instance; no secrets or profile data in Git or builds. Publish synthetic event fixtures for phase 6. Checks: backend and relay tests, not unrelated Godot suites.

---

## Phase 4 — Game account sync

Integrate phase 3 into the Godot game for browser and Windows. Owns the account module and the progression hooks (`scripts/progression.gd`, load/save and `finish_run()` in `game.gd`, identity in `net.gd`, menus in `hud.gd`).

- **Title/account UI** in the cobalt menu style with full controller navigation: **Play as Guest**, **Sign In**, account name, status **Synced / Saving / Offline / Sign-in needed**, last successful sync, retry and sign-out.
- **Sync behavior.** Login loads the server profile before allowing spending or a new account run; never upload a local cache over a newer server profile. Run results and purchases sync immediately; startup, login and returning to the title refresh. An account-scoped durable outbox holds a started run's result through disconnects and retries the same operation; pending rewards are visible but not spendable. Failures show and retry; never report a save that didn't happen. No unbounded offline account runs, and an outage never silently becomes a guest run or imports a guest balance later.
- **Existing saves.** On first login, show cloud and guest summaries. Offer one-time adoption only into an account with no progress, with preview and confirmation, leaving the local save untouched. Existing cloud progress wins; no automatic merging. Save-code export stays; importing can't overwrite an established cloud wallet. Imported codes keep friends-only trust (a checksum is not a signature).
- **Sessions and storage.** Native login uses the device flow. Tokens go in OS secure storage (Windows credential protection; Android Keystore in phase 5); where none exists, keep the token in memory and require login after restart, never plaintext. Logout or account switching separates caches and queued operations per account and offers local session cleanup without erasing guest saves. Login, logout and import stay blocked during a dig or lobby.
- **Co-op:** signed-in players join with a lobby ticket; account rejoin and host migration keep builds.
- **Activity signals** for phase 6: foreground gameplay heartbeat, platform and version.

**Done when:** progress confirmed in one browser appears in a second browser and on Windows; purchases and run results survive reloads, disconnects and lost responses without duplicates; a failed sync never says saved; pending Zenny can't be spent; switching accounts never leaks caches or results; guest progress survives login, logout and a rejected migration; a save code can't overwrite a cloud wallet; the account return trip works under COOP/COEP; co-op rejoin and host migration preserve builds. Checks: targeted progression, browser and reconnect tests against the real local backend with isolated profiles.

---

## Phase 5 — Android accounts and startup updates

- **Accounts:** phase 4's device-flow login and sync on Android, with the token in Android Keystore-backed storage. Persist pending profile operations before suspension, and handle opening the login browser as a backgrounding event.
- **Cross-play identity:** Retroid, browser and Windows share account progress and lobbies; earned progress appears on the other clients after confirmed sync.
- **Update check:** on boot, fetch `/updates/android/stable.json` with a short timeout: latest `versionCode`, display version, game protocol, minimum supported online build, download page/APK URL, byte size, SHA-256, release notes. Compare integers, not version strings. If newer, show **Update available** with notes and size, **Download update** and (when compatible) **Later**. Download opens the HTTPS page under `/downloads/android/` in the system browser; APK files are immutable and versioned with published SHA-256, size and signing fingerprint. The game doesn't claim to verify a file it never read; Android checks the signature on in-place install.
- **Update rules:** same app id and signing key with a higher `versionCode`; never require uninstalling. Never start a download or install automatically, during a dig or after **Later**. Save outbox state before leaving for the browser and refresh the profile after the update. A metadata outage doesn't block guest solo; the server still rejects incompatible online builds with the download instruction. Ship the metadata/download configuration, but don't publish files live.

**Done when:** no update, optional update, required online update, metadata outage, cancelled download, wrong signing key, no space, sleep during download and a successful in-place upgrade all behave; progress, settings and account access survive the upgrade on the real handheld; no plaintext persistent token fallback.

---

## Phase 6 — Read-only owner dashboard

A private `/admin` web page using phase 3's admin role and event data. Not a database console.

- **Views:** user search and paginated detail (display name, account id, verification, registration, last login/activity, platform, game version, profile summary, sync health); charts and tables with date filters, UTC labels, empty/error states. Emails masked in lists, shown only in authorized detail. Never render passwords, tokens, reset links or full auth tables.

| Metric | Definition |
|---|---|
| Registrations | Created accounts per UTC date |
| Logins | Success/failure from the auth service, split into sign-in, device approval, verification and session refresh. A refresh is not a login |
| DAU / WAU / MAU | Distinct account ids with foreground activity in the last 1 / 7 / 30 days, from per-account activity days (never summed daily counts) |
| Live | Current connections and lobbies; distinct accounts separately from connections |
| Play time | Foreground gameplay heartbeats, excluding background/title; labelled as an estimate |
| Game summaries | Runs, wins, deepest descent, digger usage; finalized results counted once; guests separate |
| Reliability | Sync failures/retries, auth error codes, versions and platforms; replayed receipts don't duplicate |

- **Collected fields only:** account id, opaque session/event id, server UTC time, platform (`web` / `windows` / `android`), game/protocol version and defined gameplay fields. No fingerprints, precise location, chat, passwords or tokens; no raw IPs in analytics. Client-reported platform and playtime aren't proof.
- **Retention:** detailed events 30 days, per-account activity days 90 days, aggregates 12 months, scheduled. Profiles and reward deduplication are kept as long as account correctness needs them. Export/deletion removes or anonymizes identifying analytics, and retry queues can't resurrect a deleted account.

**Done when:** anonymous and ordinary users can't fetch admin data even directly; the owner can after role bootstrap and MFA; fixtures give exact distinct-user counts across days and devices; refreshes and replays don't inflate counts; retention (tested with a fake clock) never removes deduplication; logout revokes access; accessibility, layout, paging and date boundaries are checked. No historical stats from before instrumentation.

---

## Launch: owner-supplied inputs

Development uses the substitutes; the live feature stays off until the owner supplies the real input. Never put the values in Git or documents.

| Input | Development substitute / launch gate |
|---|---|
| SMTP sender, domain and credentials | Local mail sink; public signup/recovery stays off until real delivery works |
| Owner's verified account id + MFA | Disposable admin fixture; operator assigns the real role after registration |
| Encrypted off-machine backup destination + recovery key | Isolated test destination; a restore rehearsal must pass before real account saves launch |
| Ubuntu host, service secrets, tunnel config | Local containers; the owner installs and deploys |
| Android release keystore, password, fingerprint | Debug/test key; no update promise until the release key is safely backed up |
| Retroid hardware | Automated and emulator checks first; hardware testing required to call handheld support done |

## Integration checklist (each merge)

- Review identity/contract changes and their failure cases. Nothing personal or secret staged; asset and license exceptions intact.
- After gameplay changes: export the Windows pack, refresh notices, run `tools/package-windows.ps1`, rebuild `build/RelicDiver-Web.zip`; add Android packaging checks once phase 2 lands. Don't merge stale generated bundles from parallel branches.
- Record compatibility numbers and the tests actually run (and any unavailable hardware or deployment input) in HANDOFF.md, the subsystem handoff and the status table above.

## References

Reviewed 2026-10-14; use the documentation matching the pinned versions when implementing.

- Better Auth: [installation](https://better-auth.com/docs/installation), [PostgreSQL](https://better-auth.com/docs/adapters/postgresql), [email/password](https://better-auth.com/docs/authentication/email-password), [device authorization](https://better-auth.com/docs/plugins/device-authorization), [bearer](https://better-auth.com/docs/plugins/bearer), [admin](https://better-auth.com/docs/plugins/admin).
- Godot: [Android export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html), [data paths](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html).
- Android: [app signing](https://developer.android.com/studio/publish/app-signing), [alternative distribution](https://developer.android.com/distribute/marketing-tools/alternative-distribution), [PackageInstaller](https://developer.android.com/reference/android/content/pm/PackageInstaller).
- [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252) (native-app OAuth), [RFC 8628](https://www.rfc-editor.org/rfc/rfc8628) (device authorization).
- [Retroid Pocket 5 specifications](https://www.goretroid.com/en-jp/products/retroid-pocket-5-handheld).
- Not selected: [Supabase pricing](https://supabase.com/pricing), [self-hosting](https://supabase.com/docs/guides/self-hosting).
