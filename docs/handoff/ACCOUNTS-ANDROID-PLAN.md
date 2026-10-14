# Plan: accounts, shared progress and Android

Prepared 2026-10-14 on `codex/next-features-volnutt` for merge into `main`. **Planning only; none of these features is implemented.** This extends [NEXT-FEATURES.md](NEXT-FEATURES.md). Preserve its pending co-op map/cache requests and the completed pass-16 work. The user answered all blocking product choices: [IMPLEMENTATION-DECISIONS.md](IMPLEMENTATION-DECISIONS.md) is authoritative, and [WORKER-BRIEFS.md](WORKER-BRIEFS.md) contains assignable work packages.

## Requested outcome

- Players log in and recover permanent progress on another computer, browser or Android handheld without transferring files or save codes.
- A native Android APK runs on the user's Retroid Pocket 5, uses the same account/progress and joins browser/Windows co-op lobbies.
- The APK checks for updates at startup and offers a straightforward update flow.
- The owner has an admin account and a private read-only dashboard for user/login statistics, platform/version metadata, gameplay summaries and sync health.

Accounts can ship on browser/Windows first; the admin dashboard depends on account/event instrumentation; Android can be prototyped independently, then integrated with accounts. This pass finalizes requirements and merges the planning branch. Workers implement when assigned; this pass does not provision services, spend money, deploy, submit to stores or publish releases.

## What exists today

| Area | Current implementation | Work needed |
|---|---|---|
| Permanent progress | Profile v2: records, discoveries, legacy unlocks, Zenny and four digger trees; atomic local writes and browser recovery mirror | Durable account profile, authenticated reads/writes, migration and sync |
| Transfer | Checksummed save codes with preview/confirmation | Automatic account transfer; retain guest backup/export |
| Online identity | Client-generated `online.json` id sent in `hello`; identifies reconnects, not an authenticated account | Server-verified account identity without trusting a supplied account id |
| Co-op | Browser and Windows use one WebSocket relay; deterministic floors, host migration and build sync; game protocol 6/checkpoints 3 | Android interoperability and authenticated lobby membership |
| Hosting | Node + `ws`, home PC through Cloudflare Tunnel; lobbies/checkpoints in memory; no database | Persistent storage, backup/restore and service configuration |
| Android | No export preset or APK packaging pipeline | Native export, writable paths, handheld UX, lifecycle and update check |
| Controls | Keyboard/mouse and controller menus/gameplay already implemented | Real Retroid mappings, text entry, suspend/resume and small-screen validation |

Primary integration points: `scripts/progression.gd`, progress load/save and `finish_run()` in `scripts/game.gd`, identity/reconnect in `scripts/net.gd`, `scripts/hud.gd`, `scripts/settings.gd`, sound settings paths, `server/`, `export_presets.cfg`, packaging tools and deployment docs. Do not rewrite the combat simulation to add accounts.

## 1. Accounts and permanent progress

### Selected hosting and costs

**Selected:** the existing Node server + PostgreSQL + Better Auth, deployed with Docker Compose on the owner's planned Ubuntu laptop (11th-gen i7, 16 GB RAM, 512 GB SSD), then portable to a VPS. Keep the existing domain and Cloudflare Tunnel. Accounts are independent of players' devices, while availability initially depends on the owner's server.

| Option | Tradeoff |
|---|---|
| Existing PC + persistent database volume | No new hosting subscription, but electricity/domain/backup costs remain. Saves can follow players, yet service availability and data protection still depend on this PC. A tunnel does not back up data. |
| Managed auth + database + independently hosted profile API | Alternative, not selected. Removes the profile service's home-PC dependency; co-op relay may remain at home. |
| VPS hosting API/database/relay | Removes the home-PC availability dependency for all services, but adds a paid server and owner-operated security, maintenance and backups. |

Supabase Cloud and self-hosted Supabase were evaluated but not selected. Their hosted free-tier account/storage quotas do not apply to the chosen self-hosted stack. There is no planned backend hosting subscription initially; electricity, existing domain, email delivery, off-host backups and eventual VPS/download bandwidth may cost money. Keep APKs out of the progress database. Owner approval remains required before adding paid services.

Workers ship portable deployment files, backup/restore checks and monitoring; the owner provides launch credentials and performs deployment. No measured user/concurrency capacity is claimed from hardware or prior storage examples alone.

### Account experience

Keep **Play as Guest** and add **Sign In**, account name, **Synced / Saving / Offline / Sign-in needed**, last successful sync time, retry and sign-out. Guest play remains local; only signed-in play promises shared progress. Include the limited operational/game analytics defined in IMPLEMENTATION-DECISIONS.md, not advertising analytics or device fingerprints.

**Selected:** open email/password registration using Better Auth, with verification, forgot/reset password, delivery configuration and abuse limits. Social login and email-code/magic-link login are deferred. Do not build password storage or recovery cryptography from scratch. Read-only admin privileges are assigned to the owner's verified account id by an operator command; ordinary registration cannot grant them.

For browser login, use same-origin account pages and restore the pending invite after return; test with the game's COOP/COEP headers. Windows/Android use Better Auth's first-party device-code flow with explicit approval in the system browser and bearer session validation by the backend. QR display is optional. No PKCE/app-link/loopback callback is required for this v1 device flow. Never embed a client secret or database service key in Godot, JavaScript or the APK. Implement recovery, session expiration and logout through the library.

Browser sessions should use secure HttpOnly cookies through an auth boundary where practical, with CSRF protection; do not put auth tokens in the existing progress mirror. Native long-lived credentials require platform secure storage (Android Keystore-backed storage and an appropriate Windows credential mechanism). Logout/account switching must separate caches and queued operations by account and offer local session cleanup without erasing guest saves.

### Data and sync contract

Use self-hosted PostgreSQL, schema migrations, and a server-side profile API. Required records:

- Account subject mapped to an opaque game account id and display name; keep email with the auth provider where possible.
- Versioned progress: records, discovered parts, earned/legacy unlocks, Zenny and purchased tree nodes. Settings such as controller mapping, graphics and audio stay device-local initially.
- Server revision, migration marker, and an operation ledger keyed by account and operation id, including completed run receipts and purchases. Keep credentials and lobby passwords out of profile exports.

The API derives the owner from the verified session, validates the profile/operation schema and authorizes every read/write. Client requests cannot choose another account owner or directly overwrite wallet balances. Worker A publishes the concrete `/api/v1` contract and fixtures listed in WORKER-BRIEFS.md before dependent integration starts.

1. Login loads the server profile before allowing account spending or starting a new account run. Never upload the local cache over a newer server profile.
2. Purchases are database transactions that check prerequisites, balance and expected server revision, deduct once and return the new profile. On conflict, reload and ask the player to retry the purchase; do not merge Zenny or use device timestamps to pick a winner.
3. Each run result has a stable, account-bound run/operation id. Repeated submissions after a timeout, reconnect or host migration return the existing result rather than granting rewards twice. Issue run ids through the service and retain deduplication beyond the retry window.
4. Keep an account-scoped durable outbox for a run already started when connectivity drops. Retry the same operation after reconnect; distinguish pending rewards from confirmed/spendable Zenny. Do not allow unbounded new offline account runs in v1. Guest solo remains available offline in a separate profile.
5. Permit one active account run at a time using a server lease/session rule, with explicit reconnect/takeover handling. Two devices can view progress; conflicting account play cannot silently fork the wallet. An expired lease must not discard a pending result.
6. End-of-run rewards and Workshop purchases trigger immediate sync. Startup/login and return to title refresh the profile. If sync fails, keep the pending receipt and last known profile, show the failure and retry; do not report successful cloud saving.

Cloud revision is separate from the existing local `revision`. Do not implement sync by comparing counters from different devices or summing whole profiles. Provider row policies should deny cross-account access; wallet-changing operations execute only through trusted transactions.

The current friends-co-op simulation trusts clients for important gameplay outcomes. Account authentication, validation, rate limits and deduplication prevent impersonation and accidental duplicates; they do **not** prove a reported solo/co-op result was honestly earned. Keep this trust model explicit. Competitive leaderboards, cheat-proof rewards and a dedicated authoritative simulation are separate work.

### Existing saves and active digs

On first login, show cloud and guest summaries. Offer a one-time guest adoption only when the account has no established progress; preserve the original local save and require a preview/confirmation. Existing cloud progress wins by default. Do not automatically combine wallets or trees. Validate v2 data and retain previously earned unlocks. Export remains available; importing a code must not overwrite an established cloud wallet. Imported progress has the existing friends-only trust level, since a checksum is not a signature proving rewards were earned.

Permanent account progress and active co-op checkpoints remain separate. This feature does not add solo mid-run saves or promise that any abandoned dig can be resumed on another machine. Server-verified account identity should allow rejoining a still-live compatible lobby from another device using its mirrored roster, replacing the previous connection safely. Persisting all active lobbies/checkpoints across server restarts would require a separate bounded, authorized storage design; do not imply the current memory-only relay already provides it.

### Operations and acceptance

Persist databases across container/image replacement, with a named volume and encrypted off-PC backups. Perform an isolated restore test including auth identities and admin role. Exclude databases, dumps, auth secrets, sessions and personal profiles from Git and build archives. Record sanitized auth outcome events for the admin statistics, never passwords/tokens/reset URLs. Retention, profile export/deletion and backup expiry are defined in IMPLEMENTATION-DECISIONS.md.

Acceptance: browser -> second browser -> Windows sees the same confirmed progress; purchase/result retries cannot duplicate or lose Zenny; stale/offline clients cannot overwrite newer data; account A cannot read/write B; logout and guest migration cannot mix profiles; token expiry and service outages preserve pending results; database restart/container rebuild and backup restore preserve test accounts. Use disposable accounts and isolated profiles.

## 2. Native Android APK, cross-play and startup updates

### Build and handheld support

Export the existing Godot project natively; a WebView wrapper is not the proposed approach. Retroid's [Pocket 5 specifications](https://www.goretroid.com/en-jp/products/retroid-pocket-5-handheld) list Android 13, Snapdragon 865 and a 5.5-inch 1080p display. Target ARM64 and landscape, keeping the current Compatibility renderer, supplied models, textures, audio and adventure menus. Set a 60 FPS target, with rendering resolution/quality options if device measurements require them; performance is unverified until tested on hardware.

Add a pinned Android export preset, matching engine export templates, Android SDK/JDK setup instructions and a reproducible APK packaging script. Confirm the SDK/build-tool versions against the pinned engine rather than copying future stable documentation blindly. Enable Internet permission for account HTTPS and co-op WSS. Fix Android progress, checkpoint, network identity, settings and audio writes to use writable `user://` paths; current non-web paths under `res://save/` are unsuitable for an installed APK. Preserve Windows portable saves and browser storage.

Use a stable application id, increasing Android `versionCode` and a securely backed-up release signing key. Ignore keystores/password files and inject signing configuration outside tracked presets. Keep asset and engine notices in the package and provide an in-game credits/license view. A development APK is distinct from an owner-authorized distribution build.

Validate every menu with the Retroid's real sticks, triggers, buttons, Back and controller modes, including account login, Workshop, pending cache choices, update prompts and sign-out. Test soft-keyboard entry, readable text at handheld size, safe areas and docked display behavior. General phone touchscreen combat controls are outside this initial handheld scope.

Android sleep, backgrounding, opening the login browser, Wi-Fi changes and process termination must use the existing reconnect/host-migration behavior. Do not assume a handheld can keep hosting while asleep. Test disconnect detection, takeover and exact build restoration after return; persist pending profile operations before suspension. A long suspension may exceed lobby retention and must report that honestly.

### Cross-play and account integration

Browser, Windows and Android connect to the same relay/lobby list via WSS. Keep deterministic seeds, packet encoding and combat authority unchanged. The server verifies authentication and binds the account-derived player identity before accepting rejoin or replacing a connection; a public `hello.id` is never account proof. Guest identities remain distinct and cannot impersonate account ids.

Share API schemas and progression rules across all clients. Test mixed-platform floor generation, signature attacks/bombs, tree effects, late join, choices, revive, lifts, disconnects and host migration in both directions. Gameplay compatibility, checkpoint format, profile schema and Android package version are separate numbers; change only those affected. Mixed compatible platform builds can play together, while incompatible builds receive a useful update instruction before joining.

Acceptance: real Retroid + browser + Windows share a dig; each can host and survive a host leaving; account progress earned on each appears on the other clients after confirmed sync; no save reset on an in-place APK update. Hardware performance, thermal behavior and sustained battery use require a full-run playtest, not only an emulator.

### Startup update flow

1. On boot, request small HTTPS update metadata with a short timeout. Include latest Android `versionCode`, display version, game protocol, minimum supported online build, APK URL, byte size, SHA-256 and release notes. Keep metadata fresh through CDN revalidation; use immutable versioned APK URLs. Compare integer build numbers, not version strings.
2. If newer, show **Update available**, changes/size, **Download update** and **Later** when compatible. **Selected v1:** open the trusted download page in the system browser. An integrated downloader/installer is deferred.
3. The download page/metadata uses the configured HTTPS origin/allowlist and immutable versioned files, with byte size, SHA-256 and signing fingerprint published. The game does not claim to verify a browser-downloaded APK it has not read. Android verifies signing identity for an in-place update. Any future integrated updater must verify the file itself before invoking the installer; that plugin is outside v1.
4. Use the same signing key/application id and a higher versionCode for updates. Follow Android's install-from-this-source consent and installer confirmation; do not promise silent replacement. Cancellation, low storage or an interrupted download leave the installed game usable. Never require uninstalling to update, since that can delete local pending data.
5. An unavailable update service does not stop guest solo play. Enforce incompatible-version requirements at the online service even if metadata is unavailable; block only the incompatible online operation and show the download path. Keep account reads/recovery available where schema compatibility allows.
6. Do not initiate APK installation during a dig. Preserve sync/outbox state before launching the installer, then refresh the profile after the updated app starts.

Host the eventual download/metadata on an owner-approved location on the existing domain, with appropriate bandwidth limits and notices. Do not publish a GitHub release or submit to a store as part of implementing a local APK. Initial scope is sideloading; revisit then-current Android distribution requirements before any broader release.

Acceptance: no update, optional update, required online update, metadata outage, corrupt download, wrong signing key, cancelled install, no space, sleep during download and successful in-place upgrade. Verify progress, settings and account access after upgrading on the actual handheld.

## Delivery order and launch inputs

| Step | Deliverable / completion gate |
|---|---|
| A | Backend/auth/API/schema, atomic rewards/purchases, migration, admin-role bootstrap and tested backup restore; publish the tested contract first. |
| B | Browser/Windows account UI and sync, guest protection and cross-device acceptance against the real backend. |
| C | Read-only admin dashboard, event instrumentation, distinct user metrics and retention/deletion checks. |
| D | Android development APK, writable paths, controls/lifecycle, account integration, mixed-platform co-op and browser-download startup updates. Device prototype can begin before B finishes. |
| E | Already-requested co-op map sharing, pending cache notifications/choices and chest icons; coordinate shared Godot files with B/D. |

Accounts/sync are the largest engineering and operational part. APK export is a smaller initial task; handheld lifecycle, secure login and reliable updates make the complete Android feature more than an export checkbox. Do not give a fixed schedule before the backend/device spikes establish the remaining runtime unknowns.

All blocking product questions were answered by the user on 2026-10-14; see IMPLEMENTATION-DECISIONS.md. Workers can begin their assigned packages. SMTP credentials, owner account id/MFA, backup destination, server secrets, Android release signing key and access to real Retroid hardware are later launch inputs, not unselected product options. Keep them outside Git; do not claim real deployment/hardware checks happened during planning.

After gameplay implementation, refresh the shipped Windows pack/portable ZIP and web ZIP with the existing tools, add Android packaging verification, and keep build notices and handoffs aligned. This documentation-only change requires document/link checks, not regenerated builds or a full gameplay suite. The owner performs deployment.

## Technical references

Reviewed 2026-10-14; recheck version-specific instructions during implementation.

- [Godot Android export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html) and [writable user data paths](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html).
- [Android app signing and updates](https://developer.android.com/studio/publish/app-signing), [website/sideload distribution](https://developer.android.com/distribute/marketing-tools/alternative-distribution), and [PackageInstaller](https://developer.android.com/reference/android/content/pm/PackageInstaller).
- [RFC 8252: native-app OAuth](https://www.rfc-editor.org/rfc/rfc8252) and [RFC 8628: device authorization](https://www.rfc-editor.org/rfc/rfc8628).
- [Supabase pricing](https://supabase.com/pricing) and [production checklist](https://supabase.com/docs/guides/deployment/going-into-prod), as one candidate rather than a selected provider.
- [Better Auth installation](https://better-auth.com/docs/installation), [PostgreSQL](https://better-auth.com/docs/adapters/postgresql) and [device authorization](https://better-auth.com/docs/plugins/device-authorization), the selected self-hosted integration direction; prove runtime compatibility during worker A's spike.
