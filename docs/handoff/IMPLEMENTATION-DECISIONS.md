# Implementation decisions: accounts, admin and Android

Finalized with the user on 2026-10-14. Read with [ACCOUNTS-ANDROID-PLAN.md](ACCOUNTS-ANDROID-PLAN.md) and [WORKER-BRIEFS.md](WORKER-BRIEFS.md). These are implementation requirements, **not shipped functionality**. This document supersedes earlier open questions and provider recommendations in the planning discussion.

## Confirmed user choices

| Decision | Concrete options presented | User selected |
|---|---|---|
| Backend | Existing Node + PostgreSQL + Better Auth; self-hosted Supabase; managed Supabase Free | **Existing Node + PostgreSQL + Better Auth**, self-hosted on Ubuntu initially, portable to a VPS |
| Login | Email/password; Google only; email code/link | **Email and password**, including account recovery |
| Registration | Open; invitation only; manual approval | **Anyone can register**; guest play remains available |
| Offline account progress | Online run starts/purchases with retry after disconnect; new offline account runs with reconciliation | **Start account runs and buy skills online; retry saves if disconnected mid-run**. Offline guest progress stays separate |
| Admin powers | Read-only statistics/users; add suspensions/session revocation; add audited progress editing | **Read-only statistics and user inspection** |
| APK updates | Startup check + browser download; integrated download + installer | **Startup check and open the download page in the browser** |
| Merge destination | Existing default `main`; create literal `master` | **Merge into `main`**; no new `master` branch |

Initial hardware: owner's laptop, 11th-generation i7, 16 GB RAM, 512 GB SSD, intended for Ubuntu Server. Keep the existing public game hostname `megaman.galosengen.dev` and Cloudflare Tunnel. This establishes the local-first implementation direction, not permission to install an OS, provision paid services or deploy this planning pass. The owner performs deployment.

## Engineering defaults workers can implement without another product questionnaire

### Authentication, identity and permissions

- Integrate a pinned, maintained Better Auth version with the existing Node service and PostgreSQL. Preserve current lobby/static-host behavior; do not replace the WebSocket game transport with Supabase Realtime or invent password hashing/reset protocols.
- Serve account pages and API on the game origin. Require verified email for account progression; unverified users can play as guests. Include registration, verification/resend, sign-in/out, forgot/reset password and account-session cleanup. Use a replaceable email adapter; development mail stays in an isolated local mail sink, never logs real reset tokens.
- Browser login uses same-origin secure HttpOnly sessions, CSRF/origin checks and a safe return path that preserves lobby invites. Verify browser operation with the game's threaded-export isolation headers.
- Windows/Android use Better Auth's **first-party device authorization** flow: game displays a short code and verification URL, opens the system browser when requested, and polls at the prescribed interval. The website authenticates using the chosen email/password method, displays the matching device code and requires explicit approval. Cancellation, expiry, denial, slow polling and one-time redemption are mandatory cases. A QR code is optional polish; no custom app-link/loopback callback is required for v1.
- Authenticate native API calls using the resulting session token through Better Auth's bearer integration. Use OS secure storage (Android Keystore-backed storage, Windows credential protection), not profile JSON, save codes or the browser recovery mirror. On platforms without secure persistence, keep the token in memory and require login after restart; do not silently store plaintext credentials. Verify expiration/renewal and revoke/clear on logout using the chosen library's supported session behavior.
- Obtain a short-lived, one-use lobby ticket through the authenticated profile API. The relay validates/consumes it and derives an opaque account player id; it never trusts `hello.id` as account ownership. Preserve separately namespaced guest identities. Do not put bearer/session credentials in invite URLs or routine logs.
- Assign the owner an admin role through an operator-only command using an existing verified **account id**. No first-signup promotion, client-editable role or hard-coded email/password. Admin authorization is enforced server-side on every endpoint. Require admin MFA before exposing the dashboard publicly; keep database/administration ports private. Do not enable moderation, impersonation or currency editing just because the auth library supports them.

### Progress and recovery

- Server profile is authoritative for signed-in progress. Device settings stay local. Purchases are transactional and revision-checked; run results are idempotent per account/run id. Repeated operation ids with a different body are rejected, not silently accepted.
- One active account run at a time; a second device must explicitly take over rather than starting a parallel wallet history. The server issues run ids/leases and enforces takeover. A run already started can finish through a network interruption and retain its account-bound receipt locally until acknowledged. Pending rewards cannot be spent. Expired leases must not silently erase valid pending results; define and test late receipt handling in the backend contract.
- New account runs and purchases require connectivity. Guest solo works offline in its own profile. Do not automatically convert an account outage into a guest run or import a guest balance on reconnect.
- Adopt a validated local/save-code profile once into an empty account, with preview/confirmation and an untouched local backup. No auto-merge of balances, trees or existing cloud profiles. Retain pass-16 legacy unlock migration and the current abandoned-dig accounting semantics without duplicate rewards.
- Persistent account progress transfers across devices. Rejoining a still-live compatible co-op lobby by account identity is included; durable active-lobby recovery on a different device after a server restart and solo mid-run saving are deferred. Keep existing local checkpoint/reconnect behavior.
- Authenticated profile writes remain friends-co-op trust, not proof against modified clients. No competitive leaderboard or dedicated server combat rewrite is part of this work.

### Admin dashboard and metadata

Build a private, read-only `/admin` web dashboard, with aggregate charts/tables and paginated user detail. Display name/account id, verification state, registration date, last login/activity, platform, game version, profile summary and sync health are included. Mask email in lists; show it only in authorized user detail when needed for support. Never display credentials/reset links/session tokens or download full auth tables.

| Metric/event | Definition |
|---|---|
| Registrations | Successfully created accounts, grouped by UTC date |
| Login success/failure | Auth service outcomes; distinguish sign-in, device approval, verification and session refresh. A refresh is not a new login |
| DAU/WAU/MAU | Distinct authenticated account ids with foreground game activity in the last 1/7/30 days, respectively; never sum daily distinct counts to derive monthly users |
| Active players/lobbies | Server-observed current connections/lobbies, distinct accounts separately from connection count |
| Play duration | Foreground gameplay heartbeat duration, excluding background/title time; label as estimated, not exact attention time |
| Game summaries | Runs completed, wins, deepest descent, digger usage; record finalized results once and keep guest activity separate from account statistics |
| Reliability | Profile sync failures/retries, auth outcome error codes, compatible game versions/platforms; no duplicate events for replayed receipts |

Allowlist metadata: account id, opaque session/event id, server UTC time, platform category (`web`, `windows`, `android`), game/protocol version and defined gameplay/outcome fields. Do not collect device fingerprints, precise location, chat contents, passwords or tokens. Do not persist raw IP addresses in game analytics by default; network/edge abuse controls are separate. Client-reported platform/version and playtime estimates are not trusted proof of identity.

Retention defaults: detailed login/gameplay/reliability events 30 days; per-account activity-day records 90 days to calculate distinct active-user windows; aggregate summaries 12 months. Preserve profile and reward-deduplication records as long as needed for account correctness, independently of analytics cleanup. Account export/deletion removes or anonymizes identifying analytics appropriately; do not resurrect deleted accounts through ordinary retry queues. Test retention with a fake clock and deletion with fixtures. This is operational/game analytics, not third-party advertising tracking.

### Android, updates and co-op feedback

- Native ARM64 Godot APK, landscape, current Compatibility renderer, physical-controller-first Retroid Pocket 5 support. Use writable `user://` for all Android saves/settings/identity; keep Windows portable save locations and browser recovery intact. Real handheld performance, secure token persistence and suspend/rejoin are acceptance gates, not assumptions.
- Signed APK updates preserve package id and signing identity and increase `versionCode`. Choose `dev.galosengen.relicdiver` as the application id for new development builds; once a distributed signed build exists, do not change it. Signing material belongs outside Git.
- Startup checks use a short timeout and small version metadata document at `/updates/android/stable.json`; the configured game origin hosts `/downloads/android/` and immutable versioned APKs. No APK download/installation starts automatically, during a dig or on a cancelled prompt. Offer **Later** for compatible builds. Offline metadata failure permits guest solo; incompatible online builds receive the download instruction from the server as well.
- V1 opens an HTTPS download page in the system browser. Android handles source permission and install confirmation; do not claim the game itself downloads or verifies a file it has not read. Publish the SHA-256/size and signing fingerprint for verification; no integrated downloader/installer plugin in v1.
- Keep all already-requested co-op work: party-shared map exploration/clears, pending cache-choice notification, and chest map icons. Proposed implementation defaults: a new rebindable **Pending upgrades** action on **C / RB** (currently unused), keeping **Tab / View** for Buster parts; apply notification/deferred selection to online teammate-opened caches. Preserve solo choice flow, existing choice protection, every player's queued rewards and checkpoint/rejoin restoration. Map sharing merges revealed/cleared rooms, not player positions; cleared state is host-authoritative. Show revealed caches only and distinguish claimed/pending/available state per player. No party-wide reward consumption from drawing an icon.

### Local hosting, backups and VPS migration

Use Docker Compose with persistent PostgreSQL storage, explicit schema migrations, health checks, restart policies, least-privilege service credentials and configuration via environment variables. Pin tested versions and never automatically upgrade database major versions on boot. Keep the public hostname/API stable so moving hosts does not require new game installs.

Create automated encrypted off-machine database/auth backups, initially 7 daily and 4 weekly copies, and test restoring into an isolated instance. Back up configuration/keys securely as well as database data; a Docker volume is not a backup. Database dumps, personal profiles, keystores and tokens never belong in Git or distributed builds.

Ship an operator migration checklist: prepare the VPS with compatible versions, restore a rehearsal backup, verify accounts/profiles/roles, briefly stop writes, take/restore the final backup, switch the tunnel/origin, then validate new-host writes before reopening access. Keep the old host read-only for rollback; avoid two writable copies. Existing lobbies may need to finish before cutover; do not promise zero downtime or retain every session through a signing-key change.

## Deployment inputs, not product decisions

Workers can implement and test with disposable fixtures now. These owner-supplied inputs are required **before the relevant live feature is enabled**; do not request or commit secret values in planning documents:

| Input | Safe development substitute / launch gate |
|---|---|
| SMTP sender/domain and credentials | Local mail sink; public verification/recovery remains disabled until real delivery works |
| Owner's verified account id and MFA setup | Disposable admin fixture; operator assigns the production role after registration |
| Off-machine encrypted backup destination and recovery key | Isolated test destination; restore rehearsal must pass before real account saves launch |
| Ubuntu host and private service secrets/tunnel configuration | Local isolated containers; owner installs/configures the host and deploys |
| Android release keystore/password and signing fingerprint | Separate debug/test key; no production update promise until the owner securely backs up the release key |
| Retroid hardware access | Automated/native/emulator checks first; hardware testing remains required before declaring handheld support complete |

No unresolved product choice blocks the work packages. Library compatibility, native login and secure storage still need implementation spikes; documentation research does not prove them at runtime. If a spike fails, report the concrete incompatibility and an alternative before changing the selected stack or weakening token storage.

## Validation sources

Reviewed 2026-10-14: [Better Auth installation/Node integration](https://better-auth.com/docs/installation), [PostgreSQL adapter](https://better-auth.com/docs/adapters/postgresql), [email/password](https://better-auth.com/docs/authentication/email-password), [device authorization](https://better-auth.com/docs/plugins/device-authorization), [bearer sessions](https://better-auth.com/docs/plugins/bearer), [admin roles](https://better-auth.com/docs/plugins/admin), [Godot Android export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html), and [Supabase self-hosting tradeoffs](https://supabase.com/docs/guides/self-hosting). Use documentation matching pinned dependency/engine versions when implementing.
