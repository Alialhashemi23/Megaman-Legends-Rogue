# Game account sync (phase 4)

Implemented locally on `feature/account-sync`; not pushed or deployed. The v1
server contract is unchanged, and accounts remain off unless configured.
Browser and Windows are in scope; Android sign-in remains phase 5.

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
is the phase 6 activity hook and sends no invented endpoint.

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
