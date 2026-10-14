# Account API contract (v1)

The contract between the game clients (browser, Windows, Android), the account pages and the server. Roadmap phase 3 publishes it; phases 4–6 build on it. Route names and shapes below are **final for v1**: change them only with a new version path (`/api/v2`) or an additive, optional field.

Pinned stack: Node 22 (ESM, plain `node:http`), Better Auth 1.7.7, `pg` 8.23.1, PostgreSQL 17. Verified by the phase 3 spike and `server/test/accounts.test.js`.

## Turning accounts on

Accounts are **off unless configured**; without them the server is the guest-only relay it has always been.

| Variable | Meaning |
|---|---|
| `DATABASE_URL` | `postgres://user:pass@host:5432/db`. Required for accounts |
| `BETTER_AUTH_SECRET` | ≥ 32 random characters. Required. Rotating it signs everyone out |
| `PUBLIC_ORIGIN` | The game origin, e.g. `https://megaman.galosengen.dev` (trusted origin and link base) |
| `MAIL_URL` | `smtp://user:pass@host:port` (or `smtps://`). Without it, sign-up and password reset answer `mail_unavailable` |
| `MAIL_FROM` | Sender address, e.g. `Relic Diver <noreply@galosengen.dev>` |

Schema changes are explicit: `node server/migrate.js` (Compose runs it as a one-shot `migrate` service before the game server). The server refuses to enable accounts if the schema is behind.

## Identity

- **User** (Better Auth): email, password hash, verification, sessions. Email stays here.
- **Game account**: an opaque id (`acc_` + 24 random characters) created on first use by a verified user, plus a display name. Everything below uses the game account id; clients never send an owner id.
- **Role**: `player` or `admin`, stored on the user, never settable through any API. Assigned only by `node server/admin-role.js <account id>` on the server.
- **Guests** remain unauthenticated. In co-op, guest ids from `hello.id` can never start with `acct:`; account players appear as `acct:<account id>`.

## Authentication

| Client | How it signs in | How it calls the API |
|---|---|---|
| Browser game | Same-origin pages at `/account` (sign up, sign in, verify, forgot/reset password). Returns to `/?lobby=CODE` etc. via `?return=` (relative paths only) | `better-auth.session_token` HttpOnly, Secure, SameSite=Lax cookie. Non-GET requests must send `Origin: <PUBLIC_ORIGIN>` |
| Windows / Android | Device code: game requests a code, shows it and opens `/account/device?code=XXXX-XXXX` in the system browser; the player signs in there and approves | `Authorization: Bearer <access_token>` |

Sessions last **7 days** and slide: any authenticated request more than a day after the last refresh extends them. Sign-out (`POST /api/auth/sign-out`, cookie or bearer) revokes the session immediately. An expired or revoked token gets `401 unauthorized`; the client keeps its pending operations and asks the player to sign in again.

### Device flow (native)

```http
POST /api/auth/device/code
{"client_id": "relic-windows"}                      # or "relic-android"
→ 200 {"device_code": "…", "user_code": "DZXGS7BJ", "verification_uri": "https://…/account/device",
       "verification_uri_complete": "https://…/account/device?code=DZXGS7BJ", "interval": 5, "expires_in": 600}

POST /api/auth/device/token
{"grant_type": "urn:ietf:params:oauth:grant-type:device_code", "device_code": "…", "client_id": "relic-windows"}
→ 400 {"error": "authorization_pending"}   keep polling every `interval` seconds
→ 400 {"error": "slow_down"}               add 5 s to the interval
→ 400 {"error": "access_denied"}           the player pressed Deny
→ 400 {"error": "expired_token"}           start again
→ 400 {"error": "invalid_grant"}           code already redeemed or unknown
→ 200 {"access_token": "…", "token_type": "Bearer", "expires_in": 604799}
```

Codes expire after 10 minutes and redeem once. The website side (`GET /api/auth/device?user_code=`, `POST /api/auth/device/approve|deny {"userCode"}`) requires a signed-in, verified user. Store the token in OS secure storage; never in profiles, save codes or logs.

## Errors

Every `/api/v1` error has one shape:

```json
{"error": {"code": "revision_conflict", "message": "Your progress changed on another device.", "request_id": "req_…"}, "profile": { … }}
```

| HTTP | `code` | Client should |
|---|---|---|
| 400 | `validation` | Not retry; it's a bug or tampering |
| 401 | `unauthorized` | Sign in again; keep pending operations |
| 403 | `unverified` | Ask the player to verify their email |
| 403 | `forbidden` | (admin routes, cross-site requests) not retry |
| 404 | `not_found` | Unknown run or resource for *this* account |
| 409 | `revision_conflict` | Show the returned `profile`; let the player retry the purchase |
| 409 | `active_run` | Offer **Take over** (`takeover: true`) |
| 409 | `operation_conflict` | An operation id was reused with a different body; drop the operation |
| 409 | `not_empty` | Guest adoption refused: the account already has progress |
| 413 | `too_large` | Not retry |
| 429 | `rate_limited` | Retry after `Retry-After` seconds |
| 503 | `unavailable` | Retry later with backoff; keep pending operations |

Better Auth's own routes (`/api/auth/*`) keep its error bodies (`{"code": "EMAIL_NOT_VERIFIED", "message": …}`).

## Profile

```json
{
  "account": {"id": "acc_…", "name": "Digger", "role": "player"},
  "revision": 12,
  "profile": {
    "version": 2, "kills": 140, "runs": 9, "wins": 2, "deepest": 3, "best_time": 812.5,
    "zenny": 340, "discovered": {"lens": true}, "trees": {"0": ["frame", "mobility"]},
    "legacy_unlocks": ["ember"]
  },
  "active_run": {"id": "run_…", "lease_expires_at": "2026-10-14T18:00:00Z"} | null
}
```

`profile` is the game's v2 profile (`scripts/progression.gd`) without its local `revision`. `revision` is the **server** revision: it increases by one on every change and is unrelated to the local counter. Settings stay on the device.

### `GET /api/v1/profile`

Returns the document above; creates the game account (empty profile, revision 0) on a verified user's first call. Call at startup, sign-in and on returning to the title. Never upload a local cache over it.

## Operations

All writes are `POST` with a JSON body ≤ 16 KB and a client-generated `op_id` (UUID v4) unless noted. **Replaying the same `op_id` with the same body returns the original response** (the operation ran once). The same `op_id` with a different body is `409 operation_conflict`. Operation records are kept for the life of the account.

### `POST /api/v1/runs` (start an account run)

```json
{"op_id": "…", "platform": "web|windows|android", "game_version": 7, "takeover": false}
→ 201 {"run": {"id": "run_…", "lease_expires_at": "…"}, "revision": 12}
→ 409 active_run {"active_run": {"id": "run_…", "platform": "windows", "lease_expires_at": "…"}}
```

One active run per account. A run's lease lasts **10 minutes** and is extended by heartbeats. Starting while another run's lease is live needs `takeover: true`, which supersedes the old run. Requires connectivity: the game must not start account runs offline.

### `POST /api/v1/runs/{id}/heartbeat`

No body, no `op_id`. Extends the lease to 10 minutes from now. `404` for another account's run; `409 active_run` if the run was superseded (the game keeps playing, and its result is still accepted).

### `POST /api/v1/run-results`

```json
{"run_id": "run_…", "outcome": {"won": false, "depth": 2, "guardians": 1, "scrap": 37, "kills": 41, "run_time": 655.2, "character": 1, "abandoned": false}}
→ 200 {"result": {"zenny": 117, "new_unlocks": ["ember", "coil"]}, "revision": 13, "profile": { … }}
```

The **run id is the operation id**: a run finalizes once, and retries after a timeout, reconnect or host migration return the first response. Results are accepted for any run issued to this account within **7 days**, including superseded or lease-expired runs (a lost lease never discards a result). The server derives Zenny with the game's formula, `25 × depth + 60 × guardians + floor(scrap / 5)`, and applies records exactly like `finish_run()`: runs + 1, wins, deepest, best time (wins only), kills. Bounds: depth 1–3, guardians ≤ depth, `won` requires depth 3 and 3 guardians, kills ≤ 5000, scrap ≤ 100000, run_time 0–86400 s, character 0–3. `abandoned: true` is for a saved dig the player replaced without finishing (`retire_saved_dig()`): like the game, it adds only its kills (no run, records or Zenny). **Zenny is spendable only after this returns**; until then the client shows it as pending.

### `POST /api/v1/purchases`

```json
{"op_id": "…", "character": 0, "node": "mobility", "expected_revision": 13}
→ 200 {"revision": 14, "profile": { … }}
→ 409 revision_conflict  (with the current profile)
→ 400 validation         (unknown node, prerequisite missing, already owned, not enough Zenny)
```

Atomic: checks prerequisites and balance against the stored profile, deducts once and records the node. Never merges balances.

### `POST /api/v1/discoveries`

```json
{"op_id": "…", "parts": ["lens", "coil"]}  → 200 {"revision": 15, "profile": { … }}
```

Idempotent union of valid part ids. Doesn't need `expected_revision`.

### `POST /api/v1/migrate-guest`

Adopts a guest profile (local save or save code) into an account with **no progress yet** (no runs, Zenny or purchases). Two calls:

```json
{"profile": { …v2 profile… }}
→ 200 {"preview": {"runs": 9, "wins": 2, "zenny": 340, "kills": 140, "trees": 3}, "confirm": "mig_…"}

{"op_id": "…", "profile": { …same… }, "confirm": "mig_…"}
→ 200 {"revision": 1, "profile": { … }}
→ 409 not_empty
```

The `confirm` token is bound to this account and to the exact profile (it is an HMAC of both) and expires after 10 minutes. The profile is validated with the same rules as `DiverProgression.validate()`; v1 profiles get legacy unlocks. Never merges into existing progress. Adopted progress keeps the friends-only trust level of save codes.

### `POST /api/v1/lobby-ticket`

```json
{} → 200 {"ticket": "lt_…", "expires_in": 60}
```

Single-use, 60 s. The game sends it in the relay's `hello` (`{"t": "hello", "name": …, "id": …, "v": …, "ticket": "lt_…"}`); the relay consumes it and identifies the player as `acct:<account id>` instead of `id`. A bad, expired or reused ticket gets `{"t": "error", "code": "bad_ticket"}` and the connection stays a guest. Rejoining a live lobby from another device with the same account replaces the old connection, as rejoining with the same guest id does today.

## Rate limits

Better Auth limits its own routes (sign-in and sign-up are strictest). `/api/v1` allows 60 requests per minute per account (heartbeats included) and 20 per minute per IP before sign-in; over that, `429` with `Retry-After`.

## Trust model

Accounts stop impersonation and duplicate rewards. They do **not** prove a run was earned: the game simulation is client-side and a modified client can report a fake run. This matches the friends-co-op trust the game already has; there are no competitive leaderboards.

## Fixtures

`server/test/accounts.test.js` starts a disposable PostgreSQL database, an in-memory mail sink and the server, then drives every route above with plain `fetch`, including the failure cases. It is the executable form of this document.
