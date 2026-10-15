# Owner dashboard (phase 6)

Read-only `/admin` page for the game's owner. Merged into `main` on
2026-10-14 and deployed the same day with the owner's approval. Contract details are in
[ACCOUNT-API.md](../ACCOUNT-API.md); operator setup in
[ACCOUNTS-OPS.md](../ACCOUNTS-OPS.md). Screenshots (fixture data only):
`screenshots/admin-*.png`.

## What's built

| Piece | Where |
|---|---|
| Tables (migration `002_owner_dashboard`): `analytics_event`, `activity_day`, `daily_stat`, `daily_stat_day`, `admin_mfa_session` | `server/accounts/db.js` |
| Recording, rollup, retention, queries | `server/accounts/analytics.js` |
| Login events + authenticator marking (Better Auth plugin), `twoFactor` plugin | `server/accounts/auth.js` |
| `/api/admin/*`, `/api/v1/activity`, run/replay/error events, hourly maintenance | `server/accounts/api.js` |
| Live connections/lobbies from the relay (`accounts.setLive`) | `server/server.js` |
| `/admin` page (CSP-safe SVG charts, table views, player search/detail) | `server/accounts/admin-page.js` |
| Authenticator challenge at sign-in, owner setup on `/account` | `server/accounts/pages.js` |
| Game reports foreground dig seconds (best effort, not outbox) | `scripts/account.gd` `report_activity()` |

## Access

Cookie session only (bearer tokens refused), `role = admin`, verified email,
authenticator enabled, and an authenticator (or backup-code) check recorded on
**that session** within 12 hours. Sign-out deletes the session and its check
(foreign-key cascade). Role revocation applies on the next request. There is
still no API to grant the role (`server/admin-role.js`). Players may also turn
on an authenticator through Better Auth's endpoints; only owners see the setup
button. Better Auth's "trust this device" is never sent by our pages; a trusted
sign-in would still need the step-up code on `/admin`.

## Metrics and definitions

- **Registrations:** `"user"."createdAt"` per UTC day.
- **Logins:** `login` events by method — `sign_in`, `device` (game token issued),
  `verification`, `two_factor`; outcomes `success` / `failure` / `challenge`.
  `refresh` (session expiry extended) is shown separately and is not a login.
  Device-flow `authorization_pending` / `slow_down` aren't failures.
- **DAU/WAU/MAU:** distinct accounts in `activity_day` over 1/7/30 days. A day is
  active when the account starts a dig or reports play time. Title-only visits
  and guests don't count.
- **Play time:** client-reported foreground seconds in account digs (≤300 per
  report, ≤86,400 per day). Labelled an estimate.
- **Digs:** `run_start` / `run_result` events, recorded only for first-time
  operations; replays become `replay` events. Guest digs aren't visible to the
  server, so game summaries are account-only.
- **Reliability:** `api_error` events by error code for authenticated calls
  (429s excluded), replays, protocol versions and self-reported platforms.
- **Live:** current WebSocket connections, distinct signed-in accounts, guest
  connections, lobbies with players (empty resumable lobbies separately).

No IPs, fingerprints, user agents, emails in events, chat, passwords or tokens
are stored. Emails appear masked in the list and in full only in the detail.

## Retention

Hourly (and before every stats request) `rollup()` stores aggregates for each
complete UTC day; `prune()` then deletes events older than 30 days, activity
days older than 90, aggregates older than 366. Today is always computed live.
Profiles, runs and the `operation` ledger are never pruned. Deleting a user
cascades to their events and activity days; a deleted account's tokens get 401,
so queued retries can't recreate it. No history exists before deployment.

## Checks

- `server/test/admin.test.js` (6): anonymous/player/bearer refusal; role + MFA
  setup + sign-in challenge + backup code + 12 h expiry + step-up + sign-out +
  role revocation; exact distinct counts across days/devices, capped play time,
  replays not double-counted, refresh separate from sign-in, failed sign-in,
  date validation; masked list vs detail; retention with a fake clock keeping
  summaries and replay deduplication; user deletion; live relay counts.
- Full server suite with disposable PostgreSQL: **42/42**. The first live deploy
  returned 503 on `/api/admin/*` because `createAccounts` had no default clock
  (tests always injected one); fixed and redeployed 2026-10-14, with a test that
  starts the dashboard without a clock as production does.
- `tests/account_checks.gd`: **37/0** (3 new: play-time report, outside the
  outbox, none without confirmed sign-in). `tests/android_checks.gd` 44/0.
- `server/test/admin-preview.mjs` renders desktop/narrow/player/code screens in
  headless Edge via `playwright-core` (set `PLAYWRIGHT_MODULE`, `BROWSER_PATH`).

## Before it goes live (owner decisions)

1. Done: merged; web ZIP, Windows pack/ZIP and APK build 4 refreshed (older
   builds still work; they just don't report play time).
2. Done 2026-10-14: on-demand backup `daily/relic-20261015-021600.dump.enc`,
   then `docker compose up -d --build`; `migrate` created `twoFactor`, added
   `twoFactorEnabled` and applied `002_owner_dashboard`. Live checks: healthz,
   `index.pck` SHA matches `build/web`, `/admin` 200, `/api/admin/me` 401
   anonymous, account page serves the authenticator step, Android update
   routes still 404 (not published). The owner's verified account was granted
   admin with `server/admin-role.js`.
3. **Owner still to do:** on `/account`, set up the authenticator and store the
   backup codes in the password manager, then open `/admin`. Counts start from
   this deployment.

Not done: no historical backfill, no CSV export, no alerting. Admin MFA rate
limiting relies on Better Auth's two-factor limits (3 per 10 s) plus the API's
per-IP limit.
