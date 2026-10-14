# Plan: accounts, shared progress and Android

Prepared 2026-10-14 for `codex/next-features-volnutt`. **Planning only; none of these features is implemented.** This extends [NEXT-FEATURES.md](NEXT-FEATURES.md). Preserve its pending co-op map/cache requests and the completed pass-16 work.

## Requested outcome

- Players log in and recover permanent progress on another computer, browser or Android handheld without transferring files or save codes.
- A native Android APK runs on the user's Retroid Pocket 5, uses the same account/progress and joins browser/Windows co-op lobbies.
- The APK checks for updates at startup and offers a straightforward update flow.

These are two separate features with shared dependencies: accounts can ship on browser/Windows first; Android can be prototyped independently, then integrated with accounts. This request authorizes planning, not implementation, spending, deployment, store submission or release publication.

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

### Hosting and costs: decision still open

The user asked whether separate hosting costs money; no hosting or login choice has been selected. Distinguish **independent of the player's device** from **independent of the owner's PC**.

| Option | Tradeoff |
|---|---|
| Existing PC + persistent database volume | No new hosting subscription, but electricity/domain/backup costs remain. Saves can follow players, yet service availability and data protection still depend on this PC. A tunnel does not back up data. |
| Managed auth + database + independently hosted profile API | Recommended if saves should be independent of the owner's PC. The API can use provider functions rather than a second always-on server. Co-op relay may remain at home; multiplayer still depends on it. |
| VPS hosting API/database/relay | Removes the home-PC availability dependency for all services, but adds a paid server and owner-operated security, maintenance and backups. |

As a concrete option, [Supabase pricing](https://supabase.com/pricing) checked 2026-10-14 lists a $0 plan with 500 MB database and 50,000 monthly active users, pausing after one inactive week and without automatic backups. Pro starts at US$25/month with daily backups. These are provider allowances, not an estimate of the entire system's cost. API execution, email delivery, off-host backups and APK download bandwidth need separate budgeting; verify quotas at implementation time. Keep APKs out of the progress database and do not assume free-tier reliability or permanent pricing.

The implementation proposal should identify a free pilot option, backup arrangement, and explicit paid upgrade threshold before any service is provisioned. Do not select or purchase a provider as part of this document change.

### Account experience

Proposed default: keep **Play as Guest** and add **Sign In**, account name, **Synced / Saving / Offline / Sign-in needed**, last successful sync time, retry and sign-out. Guest play remains local; only signed-in play promises shared progress. Track the gameplay data needed to restore progress, not advertising analytics or device fingerprints.

Use a maintained authentication service. Email code/link is an initial recommendation, not an accepted choice; social login is another option. Email login requires real delivery configuration and abuse limits. Avoid building password storage, reset and recovery from scratch.

For browser login, use a top-level redirect and restore the pending invite after return; test with the game's COOP/COEP headers. Native clients use a system-browser authorization flow with PKCE and a validated return route. A short-lived device-code/QR flow is a useful handheld alternative if the selected provider supports it. Never embed a client secret or service-role database key in Godot, JavaScript or the APK. Provide account recovery and session revocation through the provider.

Browser sessions should use secure HttpOnly cookies through an auth boundary where practical, with CSRF protection; do not put auth tokens in the existing progress mirror. Native long-lived credentials require platform secure storage (Android Keystore-backed storage and an appropriate Windows credential mechanism). Logout/account switching must separate caches and queued operations by account and offer local session cleanup without erasing guest saves.

### Data and sync contract

Use a persistent relational database (managed PostgreSQL is a candidate), schema migrations, and a server-side profile API. Proposed records:

- Account subject mapped to an opaque game account id and display name; keep email with the auth provider where possible.
- Versioned progress: records, discovered parts, earned/legacy unlocks, Zenny and purchased tree nodes. Settings such as controller mapping, graphics and audio stay device-local initially.
- Server revision, migration marker, and an operation ledger keyed by account and operation id, including completed run receipts and purchases. Keep credentials and lobby passwords out of profile exports.

The API derives the owner from the verified session, validates the profile/operation schema and authorizes every read/write. Client requests cannot choose another account owner or directly overwrite wallet balances. Candidate operations are `GET profile`, `POST run-result`, `POST purchase`, and `POST migrate-guest`; endpoint names remain implementation choices.

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

Persist databases across container/image replacement. For self-hosting, add a named volume and an off-PC backup destination; for managed hosting, verify retention and export access. Perform an isolated restore test. Exclude databases, dumps, auth secrets, sessions and personal profiles from Git and build archives. Keep auth failures/token-bearing URLs out of logs and minimize operational log retention; provide profile export/deletion and document backup expiry.

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
2. If newer, show **Update available**, changes/size, **Download update** and **Later** when compatible. MVP can open the trusted download page in the system browser; an integrated download/install plugin is a later UX improvement, not required for startup checking.
3. Download only from the configured HTTPS origin/allowlist. An integrated updater verifies size/hash, package id/version and expected signing identity, then invokes Android's installer with a scoped content URI/appropriate install permissions. A hash from the same server detects corruption, not an independently compromised update server; Android's signing identity is essential.
4. Use the same signing key/application id and a higher versionCode for updates. Follow Android's install-from-this-source consent and installer confirmation; do not promise silent replacement. Cancellation, low storage or an interrupted download leave the installed game usable. Never require uninstalling to update, since that can delete local pending data.
5. An unavailable update service does not stop guest solo play. Enforce incompatible-version requirements at the online service even if metadata is unavailable; block only the incompatible online operation and show the download path. Keep account reads/recovery available where schema compatibility allows.
6. Do not initiate APK installation during a dig. Preserve sync/outbox state before launching the installer, then refresh the profile after the updated app starts.

Host the eventual download/metadata on an owner-approved location on the existing domain, with appropriate bandwidth limits and notices. Do not publish a GitHub release or submit to a store as part of implementing a local APK. Initial scope is sideloading; revisit then-current Android distribution requirements before any broader release.

Acceptance: no update, optional update, required online update, metadata outage, corrupt download, wrong signing key, cancelled install, no space, sleep during download and successful in-place upgrade. Verify progress, settings and account access after upgrading on the actual handheld.

## Suggested delivery order and remaining decisions

| Step | Deliverable / completion gate |
|---|---|
| A | Select hosting and login method; document budget, recovery, offline/concurrent-device policy and exact auth integration. No paid provisioning without an owner decision. |
| B | Durable schema, auth/profile API, authorization, atomic rewards/purchases, migration and tested backup restore using disposable accounts. |
| C | Browser/Windows account UI and sync; cross-device acceptance checks. Existing co-op and guest saves remain usable. |
| D | Android development APK: storage fixes, real Retroid controls, full solo run and mixed-platform co-op. The device prototype can begin before account integration is finished. |
| E | Android account flow, lifecycle/rejoin, signed upgrade and startup update check; hardware acceptance and packaging/handoffs. |

Accounts/sync are the largest engineering and operational part. APK export is a smaller initial task; handheld lifecycle, secure login and reliable updates make the complete Android feature more than an export checkbox. Do not give a fixed schedule before the hosting/login choice and device spike establish the unknowns.

Still open: managed versus self-hosted services and budget; email/social login and recovery; acceptance of online-required account starts/purchases with separate offline guest play; whether active-dig transfer beyond live-lobby rejoin is needed; browser-download versus integrated APK installer for the first version. The defaults above are proposals, not user-approved implementation details.

After gameplay implementation, refresh the shipped Windows pack/portable ZIP and web ZIP with the existing tools, add Android packaging verification, and keep build notices and handoffs aligned. This documentation-only change requires document/link checks, not regenerated builds or a full gameplay suite. The owner performs deployment.

## Technical references

Reviewed 2026-10-14; recheck version-specific instructions during implementation.

- [Godot Android export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html) and [writable user data paths](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html).
- [Android app signing and updates](https://developer.android.com/studio/publish/app-signing), [website/sideload distribution](https://developer.android.com/distribute/marketing-tools/alternative-distribution), and [PackageInstaller](https://developer.android.com/reference/android/content/pm/PackageInstaller).
- [RFC 8252: native-app OAuth](https://www.rfc-editor.org/rfc/rfc8252) and [RFC 8628: device authorization](https://www.rfc-editor.org/rfc/rfc8628).
- [Supabase pricing](https://supabase.com/pricing) and [production checklist](https://supabase.com/docs/guides/deployment/going-into-prod), as one candidate rather than a selected provider.
