# Game account sync (phase 4)

## In-game sign-in and the Guest rule — 2026-10-16 (build 30)

Owner direction: sign-in is a modal on the same screen on every platform, and
Guest progress follows one rule. `DiverAccount.settle_guest()` runs whenever an
account becomes active (sign-in, browser cookie session at startup, Android
restore): if the account is empty and Guest has progress, it previews and
confirms `/api/v1/migrate-guest` by itself, and clears Guest once the server
confirms; otherwise (or on `not_empty`) `game.discard_guest_progress()` resets
the Guest archive, its browser mirror and a saved Guest dig. Sign-out therefore
returns to a fresh Guest. Account caches, outboxes and checkpoints are untouched.

The panel (`hud.gd draw_account()`, drawn over an inert title) has Sign in,
Create account, Forgot password, Authenticator code (TOTP or backup code) and
Check your email views, with LineEdits that controller confirm focuses and Enter
advances. `account.gd` posts to Better Auth (`sign-in/email`, `sign-up/email`,
`request-password-reset`, `two-factor/verify-totp|verify-backup-code`) with no
bearer. Browsers rely on the cookie; native clients send `Origin: <server>`,
read `set-auth-token`, and send the `two_factor` cookie back themselves
(`request_headers()`). The owner account has an authenticator, so this step is
required for them. The device flow, its polling and the manual adoption buttons
are gone from the game; the server keeps the device endpoints for old APKs.
Invite links join their lobby once sign-in finishes.

Diagnosis that led here (read-only): one account only; Android (old APK 4)
synced runs and purchases to it; the browser sent nothing after Oct 14, so the
owner's later playtesting stayed in that browser's Guest save. The owner chose to
let the rule discard that browser Guest progress.

Checks: account 56 (sign-in errors, authenticator cookie/headers, bearer,
create/reset, automatic adoption, account-wins discard incl. saved Guest dig,
modal fields/Back), Android 48, UI 47, options 39, progression 309, resume 24,
co-op feedback 40, smoke, persistence; `tests/account_e2e.mjs` against disposable
PostgreSQL with Playwright: native password + authenticator sign-in through a
response-dropping proxy, browser modal sign-in with a TOTP code from an invite,
purchase, reload (cookie session kept), second browser and Windows sync.

Implemented on `feature/account-sync` (`084d6a6`), merged into `main` through `dec0ddc`, and deployed with the
user's authorization on 2026-10-14. Godot exports and Docker builds ran locally
on the Windows PC. Public health, exact pack SHA256, isolation headers and the
WebSocket hello passed at https://megaman.galosengen.dev. Cloudflare only tunnels
traffic to the local server. Accounts are enabled locally as of 2026-10-14 with
the user's explicit approval: PostgreSQL 17.11, generated auth secrets, verified
`mail.galosengen.dev` and a separate sending-only Resend SMTP key. The v1 server
contract is unchanged.
This handoff covers browser and Windows. Android device-flow sign-in, encrypted
session persistence and lifecycle integration are implemented in phase 5 on
`feature/android-accounts` and merged into `main` through `dec0ddc`; see [ANDROID.md](ANDROID.md) for checks and open
hardware acceptance. Windows remains memory-only. The owner registered and
confirmed their live email; their game account/profile and session were verified
in the database without inspecting credentials.

## Live account operations

The ignored `.env` selects both Compose files through `COMPOSE_FILE`; ordinary
Compose updates preserve account services. Never commit it or print credentials.
Open/click tracking is disabled for account emails. Local/public health, account
page and session routes passed; unauthenticated profiles correctly return 401.
SMTP authentication passed without sending email. Actual inbox delivery and the
owner's sign-up/confirmation still need the owner to exercise the live flow.

Daily encrypted backups keep 7 daily and 4 weekly copies in
the off-machine synced folder set as `BACKUP_HOST_DIR` in the host's `.env`. Backup startup now
waits for migrations. A fresh post-migration backup passed checksum/decryption
and restored into a disposable database on an isolated Docker network; all 11
public tables matched, then test resources were removed. Production data was
not changed by the rehearsal. Confirm OneDrive syncing and separately retain
`BACKUP_PASSPHRASE` and `BETTER_AUTH_SECRET` in an off-machine password manager.
The original management key supplied in chat is not used by the game; the owner
can revoke it independently of the separate SMTP key.

## Ownership and storage

`scripts/account.gd` (`DiverAccount`) owns queued HTTP, authentication, device
polling, revisions, outbox, retries, run leases, migration and tickets. `game.meta`
is the active view; `profile_source` selects Guest/account. Guest data remains
separate and is restored on sign-out. Cloud operations never write archive.json.

Account files use `DiverPaths.pick("res://save/accounts", "user://accounts")`,
under the validated account id. `profile.json` contains confirmed progress and
server revision; `outbox.json` contains ordered immutable operations; `active.json`
contains a durable run-start intent or account run id + shared co-op world id.
Each digger has their own server run id, independent of the host's world id.
Writes use temporary files and rename; browser storage also keeps synchronous,
account-scoped localStorage recovery copies while IndexedDB commits.

Windows credentials are **memory-only** (the brief's permitted fallback). Sign
in again after restarting; the same account's durable outbox resumes. Tokens
never appear in profiles, settings, online identity, save codes or logs.

Startup/login/title fetch authoritative progress. Older idempotent receipts
cannot roll a newer wallet backwards. A 401 keeps pending operations and asks
for sign-in. Network/5xx/429 failures back off; terminal 4xx errors surface and
remove only the refused operation. Pending rewards are visible and unspendable.
Revision conflicts adopt server progress and require a new explicit purchase.
Profile 3 (polish P4): purchases follow the Workshop grid rule (buy a node linked
to an owned one; trees must stay connected through `frame`). `buy()` and
`applyOutcome()` stamp stored profiles to version 3. Stored v2 data needs no
database migration because every v2 tree is a valid connected grid tree.
Profile 4 (P5) adds the `spec_a`/`spec_b` grid nodes. Which specialization is
equipped is a per-device setting, not account data, so it needs no server operation.

## Menus, invites and co-op

Title's account entry preserves Start Dig's default focus. Account menus use
existing navigation targets. Browser sign-in stays in the same tab and preserves
the relative path/query in `return`. Accounts-enabled guest invites offer
sign-in or Continue to invited lobby before entering; accounts-disabled servers
keep automatic guest invites. Windows shows the code/countdown/Open page/Cancel.
Slow-down, denial and expiry follow the device contract.

The account page compares Guest/cloud summaries. Empty accounts can preview and
confirm adoption from local progress or a save code; established wallets cannot
be replaced. Sign-out restores Guest. Optional local cleanup refuses to erase
pending operations. Sign-in/out/import remain blocked during digs/lobbies.

Fresh tickets precede each WebSocket hello and queued lobby command.
`welcome.account` selects `acct:` identity; online.json retains the guest id.
Bad tickets fall back to guests with a notice. Protocol 7 and checkpoint version
3 remain unchanged; account checkpoint fields are optional. Local checkpoints
guard account ownership and recover that digger's issued run id. Heartbeats run
every 120 seconds; losing the lease still allows results. `foreground_seconds`
is reported to `POST /api/v1/activity` (phase 6 branch; see OWNER-DASHBOARD.md).

## Checks

- `tests/account_checks.gd`: 34 passed (durable client recreation, retries,
  pending rewards, 401/conflicts, switching, guest isolation, migration refusal,
  navigation, device slow-down/denial/expiry, safe cleanup).
- Progression 138, resume 24, co-op feedback 40, UI 47, Options 39 passed; smoke
  passed; `tests/net_test.sh` reconnect/host migration/server restart passed.
- Server npm tests with disposable PostgreSQL: 34 passed, none skipped.
- `tests/account_e2e.mjs`: disposable real API + Godot HTTP transport; drops
  committed result/purchase responses, verifies cross-process progress and real
  ticket handshake. Set `TEST_DATABASE_URL` and `GODOT`; `PLAYWRIGHT_MODULE`
  enables browser sign-in/invite, purchase, reload and cross-device coverage.
  Browser sign-in/invite, in-game purchase, reload, second browser and Windows
  synchronization passed under COOP/COEP. Browser storage-success values use
  explicit `bool()` conversion at the JavaScript bridge boundary.

Tests use isolated paths/databases. Never target personal profiles or deployment
databases. Packaging must refresh web ZIP, Windows pack and portable ZIP together.
