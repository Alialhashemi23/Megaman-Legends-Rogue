# Phase 4 brief: game account sync (browser + Windows)

Self-contained handoff for the next implementer (prepared 2026-10-14 for a Codex session). Read in this order: this file → [../ACCOUNT-API.md](../ACCOUNT-API.md) (the server contract; **don't change it**) → [ROADMAP.md](ROADMAP.md) phase 4 section (requirements and "done when") → [../../AGENTS.md](../../AGENTS.md) rules. Skim [NETWORK.md](NETWORK.md) only for the relay `hello` change.

## Where things stand

- `main` at `dddeb9b`: phases 1–3 merged. The **server** side of accounts is finished and tested (`server/accounts/`, 34/34 server tests). The **game** knows nothing about accounts yet; that is this phase.
- Accounts are off on the live site. Develop against a local stack (below). Don't deploy, don't touch the live `megaman-legends-rogue-*` containers, don't push without the user's go-ahead. Work on a branch: `feature/account-sync`.
- Android account support is phase 5. Build the shared pieces so Android can reuse them, but only browser and Windows are in scope. Admin dashboard is phase 6.

## Local backend for development

```sh
# .env.dev (not committed): POSTGRES_PASSWORD, BETTER_AUTH_SECRET, BACKUP_PASSPHRASE (any long values),
# PUBLIC_ORIGIN=http://127.0.0.1:18080, MAIL_URL=smtp://mailpit:1025
# ports.yml override (not committed) so the live stack on :8080 is untouched:
#   services: {relic-diver: {ports: !override ["127.0.0.1:18080:8080"]}, cloudflared: {profiles: ["never"]}, mailpit: {ports: !override ["127.0.0.1:18025:8025"]}}
docker compose -p relic-dev --env-file .env.dev -f docker-compose.yml -f docker-compose.accounts.yml -f ports.yml --profile dev-mail up -d --build
# Verification emails: http://127.0.0.1:18025   Game + API: http://127.0.0.1:18080
# Tear down: same command with `down -v`  (only ever with -p relic-dev)
```

The server serves the **web build** from `build/RelicDiver-Web.zip` baked into the image, so browser testing needs `tools/package-web.ps1` then a rebuild of the dev stack. The Windows build talks to the API over HTTP(S) from Godot directly. Server unit/contract tests: `cd server && TEST_DATABASE_URL=postgres://postgres:test@127.0.0.1:55432/postgres npm test` (see the header of `server/test/accounts.test.js`).

## What to build

### 1. Account client module (new `scripts/account.gd`, `class_name DiverAccount`)

One node owned by `game.gd`, separate from the combat code. Responsibilities:

- **HTTP:** a small queue over `HTTPRequest` with JSON bodies, timeouts and the contract's error shape (`error.code`). Base URL: the page origin on web (relative `/api/v1/...`); on Windows derive `https://<host>` from `net.server_url` (`wss://host/ws` → `https://host`), with the existing `relic_diver/online/default_server` as the default.
- **Auth state:** `guest | signing_in | signed_in | needs_sign_in`, account `{id, name, role}`, last sync time, status `Synced / Saving / Offline / Sign-in needed`.
  - **Web:** cookie session; just call `GET /api/v1/profile` (same-origin, cookies sent automatically). Sign-in happens on `/account?return=/...` — open it in the same tab (`JavaScriptBridge`), preserving a pending `?lobby=` invite in `return`. Non-GET requests from the page carry `Origin` automatically. Verify it works under the game's COOP/COEP headers.
  - **Windows:** device flow (`POST /api/auth/device/code` with `client_id: "relic-windows"`, show the `user_code` big in the cobalt menu, `OS.shell_open(verification_uri_complete)`, poll `/api/auth/device/token` at `interval`, add 5 s on `slow_down`, stop on `access_denied` / `expired_token`). Store the token with **Windows credential protection** (e.g. a tiny DPAPI helper via `OS.execute` on PowerShell `ConvertFrom/To-SecureString`, or keep it in memory only). **Never** write it to `archive.json`, `online.json`, `settings.json`, save codes or logs. If no secure store is available, memory-only and sign in again next launch (the roadmap allows this; no plaintext fallback).
- **Account-scoped cache:** a separate local file per account id (e.g. `user://accounts/<id>/profile.json` via `DiverPaths`) holding the last confirmed server profile + revision, plus a **durable outbox** (`outbox.json`) of pending operations. Guest `archive.json` is never overwritten by account data.

### 2. Progress model switch

`game.meta` today is the guest profile (`scripts/progression.gd` v2, saved by `save_meta()`). When signed in, the game must read and spend from the **server** profile instead:

- Keep `game.meta` as "the active profile" for the rest of the code, but route writes: guest → existing `save_meta()`; account → the outbox/API and the account cache. Easiest: a `profile_source` flag on game plus guarded branches at the four write sites below. Don't scatter HTTP calls through `game.gd`.
- **Startup / sign-in / return to title:** `GET /api/v1/profile`, replace the account view of `meta` with `profile` + `revision`. Never upload local data over it.
- **Pending Zenny:** results in the outbox aren't spendable. Show them as "+N pending" in the Workshop/results; disable purchases that would need them.

Write sites to route (all in `scripts/`):

| Site | Today | Signed in |
|---|---|---|
| `start_run()` (game.gd:260) | local only | `POST /api/v1/runs` first (online only). `409 active_run` → offer **Take over** (cobalt confirm, second click) → retry with `takeover: true`. Can't reach the server → say so and offer guest play; **don't** start an offline account run. Keep `run_id` (server's) for the result. Heartbeat `POST /runs/{id}/heartbeat` every ~2 min while in a dig; `409` there = taken over elsewhere: keep playing, show a notice |
| `finish_run()` (game.gd:962) | adds Zenny/records, `save_meta()` | Put `{run_id, outcome}` in the outbox **before** sending (outcome: `won, depth, guardians = depth-1+int(guardian_dead), scrap, kills, run_time, character`); send; on 200 replace profile from the response; on network error/503 keep it pending and retry with backoff (same body, same run id). Results screen shows Zenny as pending until confirmed |
| `buy_skill()` (game.gd:1027) | local spend + save | `POST /purchases {op_id, character, node, expected_revision}`; generate `op_id` once and persist it in the outbox before sending. `409 revision_conflict` → replace profile from the response, show "your progress changed on another device", let the player retry. Disabled while offline |
| discoveries (`player.gd` `add_item`, ~line 307) | `meta.discovered[id] = true; save_meta()` | queue `POST /discoveries {op_id, parts:[id]}` (batch is fine) |
| `retire_saved_dig()` (game.gd:1494) | adds abandoned kills | if that dig was an account run, send its result with `abandoned: true` |

Outbox rules: operations keyed by account id; replay in order; same `op_id`/`run_id` + same body on every retry; drop only on 2xx or a non-retryable 4xx (`validation`, `operation_conflict`, `not_found`), surfacing it. `401` → status "Sign-in needed", keep the outbox. Persist the outbox before every send.

### 3. UI (hud.gd, cobalt style, mouse + keyboard + controller)

- **Title:** account panel: `Play as Guest` (current behavior) / `Sign In` / signed-in name + status line (`Synced`, `Saving…`, `Offline – will retry`, `Sign-in needed`) + last sync time + `Retry` + `Sign Out`. Add menu mode(s) to `MENU_MODES` with full `nav_*` support (see how `workshop` / `save_codes` are done around hud.gd:375).
- **Device code screen** (Windows): big code, "Open sign-in page" button, cancel, expiry countdown.
- **First sign-in with existing guest progress:** show both summaries. If the account is empty, offer **Use this PC's progress** → `POST /migrate-guest {profile}` (preview) → confirm screen → `POST /migrate-guest {op_id, profile, confirm}`. If it isn't empty: cloud progress wins; guest save stays untouched locally. Never auto-merge.
- **Save codes** while signed in: export works (exports the account view); **import is blocked** for an established account (offer it only as the migrate-guest source when the account is empty).
- Sign-in/out and import stay blocked during a dig or lobby (same guard the save-code import already uses).

### 4. Co-op identity

In `net.gd` `hello` (net.gd:246): if signed in, first `POST /api/v1/lobby-ticket`, then send `{"t":"hello", …, "ticket": ticket}`. Fetch a fresh ticket on every (re)connect (tickets are single-use, 60 s). `welcome.account == true` confirms; `error bad_ticket` → continue as guest and show a quiet notice. Guests unchanged. **Don't** bump `NET_VERSION` for this (the relay change is backward compatible; the game packet protocol is unchanged).

### 5. Activity signal for phase 6 (small)

Not part of the contract yet. Leave a clearly marked hook (e.g. `DiverAccount.foreground_seconds`) but don't invent endpoints.

## Acceptance (from the roadmap, adapted)

1. Progress confirmed in browser A appears after sign-in in browser B and in the Windows build.
2. Purchases and run results survive reload, disconnect and a lost response with no duplicates (kill the server mid-request; test against the dev stack).
3. A failed sync never shows "Synced"/"Saved"; pending Zenny can't be spent.
4. Switching accounts never shows the other account's cache or sends its outbox.
5. Guest progress survives sign-in, sign-out and a rejected migration; a save code can't overwrite an established cloud wallet.
6. Browser sign-in returns to a pending `?lobby=` invite and works with COOP/COEP.
7. Signed-in co-op: relay shows `acct:` identity; rejoin from another device replaces the old connection; host migration keeps builds.
8. Existing suites still pass: `tests/progression_checks.gd`, `run_resume_checks.gd`, `coop_feedback_checks.gd`, `ui_checks.gd`, `options_checks.gd`, `--smoke-test`, `server npm test`, `tests/net_test.sh`. Add `tests/account_checks.gd` (headless; fake HTTP responses through an injectable transport) covering outbox replay, conflict handling, account switching and guest isolation. Optionally a Playwright browser test against the dev stack.

## Pitfalls

- Test saves must use isolated paths (`save_path`, `checkpoint_path`, test account cache dirs). Never touch the user's `save/` profiles.
- Stale Godot class cache → "undeclared Diver*" errors: run `--headless --editor --path . --import` (TECHNICAL.md). After adding `class_name DiverAccount`, the same import is needed.
- `Start-Process -ArgumentList` splits `"Windows Desktop"`; use `& godot.exe ... "Windows Desktop"`. Web exports need the real `%APPDATA%` (templates live there), tests use `tools/runtime`.
- Better Auth needs the request `Origin` to equal `PUBLIC_ORIGIN` for cookie POSTs; the Windows client uses bearer tokens and doesn't send cookies.
- Keep `server/accounts/rules.js` and `scripts/progression.gd` in sync if you touch either; `server/test/rules.test.js` enforces it.
- After gameplay changes: rebuild web ZIP + Windows pack + portable ZIP (HANDOFF.md "Live deployment" commands, minus `docker compose`), update CHANGELOG, HANDOFF, ROADMAP status.
