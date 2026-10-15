# Running accounts (operator guide)

How to turn on player accounts for the self-hosted server, back them up, and move to another machine. The API contract is in [ACCOUNT-API.md](ACCOUNT-API.md). Accounts are **off** until configured. With no accounts add-on selected, `docker compose up -d` runs the guest-only game. The live Windows deployment's ignored `.env` now selects both Compose files through `COMPOSE_FILE`, keeping accounts enabled for default Compose commands.

## What gets added

| Service | Role |
|---|---|
| `postgres` (17.11) | Account database, in the `relic-db` named volume. No port is published |
| `migrate` | Applies schema changes and exits; the game server waits for it |
| `relic-diver` | Same game server, now with `/account`, `/api/auth` and `/api/v1` |
| `backup` | Encrypted dump after migrations finish and daily; keeps 7 daily + 4 weekly |
| `mailpit` (only with `--profile dev-mail`) | A fake inbox at http://localhost:8025 for testing |

## First-time setup

1. **Secrets in `.env`** (never commit it). Generate each with `node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))"`:
   - `POSTGRES_PASSWORD`, `BETTER_AUTH_SECRET` (changing it later signs everyone out), `BACKUP_PASSPHRASE`.
   - Store `BACKUP_PASSPHRASE` and `BETTER_AUTH_SECRET` somewhere **off this machine** (a password manager). Backups are useless without the passphrase.
2. **Backups off the machine:** set `BACKUP_HOST_DIR` to a folder that leaves this computer: a NAS share, a synced cloud folder (OneDrive, Dropbox, Google Drive) or a USB drive you rotate. The default `./db-backups` is on the same disk and only protects against mistakes, not a dead drive.
3. **Mail:** set `MAIL_URL` (`smtp://user:password@host:587`) and `MAIL_FROM` from a mail provider; your domain needs that provider's SPF/DKIM records. Until `MAIL_URL` works, sign-up and password reset answer *"account emails aren't set up"*, so no unverifiable accounts are created.
4. **Start:**
   ```sh
   docker compose -f docker-compose.yml -f docker-compose.accounts.yml up -d --build
   docker compose -f docker-compose.yml -f docker-compose.accounts.yml logs migrate relic-diver backup
   ```
   Expect `Account database is up to date.`, `Accounts enabled for https://megaman.galosengen.dev` and a `backup …` line.
5. **Admin role:** sign up on `/account` with your own email, confirm it, then find your account id (`acc_…`) from `GET /api/v1/profile` while signed in, or from the database. Then:
   ```sh
   docker compose -f docker-compose.yml -f docker-compose.accounts.yml exec relic-diver node server/admin-role.js acc_XXXX
   docker compose -f docker-compose.yml -f docker-compose.accounts.yml exec relic-diver node server/admin-role.js --list
   ```
   `--revoke` removes it and signs that account out everywhere. No web page or API can grant the role.
   **Owner dashboard (phase 6):** once you're admin, open `/account`, choose *Set up authenticator for the owner dashboard*, enter your password, add the setup key to an authenticator app, save the backup codes in your password manager, and confirm a code. Then open `/admin`. Each browser session asks for a code again after 12 hours. Losing both the app and the backup codes means an operator must clear your authenticator in the database (`delete from "twoFactor" where "userId" = …; update "user" set "twoFactorEnabled" = false where id = …`).
6. **Rehearse a restore** (below) once before telling players their progress is saved.

To test locally first, add `MAIL_URL=smtp://mailpit:1025`, use `--profile dev-mail`, and read the emails at http://localhost:8025.

## Updating

`docker compose -f docker-compose.yml -f docker-compose.accounts.yml up -d --build` rebuilds the game image, re-runs `migrate` (it only applies what's missing) and restarts. Data lives in the `relic-db` volume and survives rebuilds. **Never** run `docker compose down -v` on the real stack: `-v` deletes the database volume. PostgreSQL is pinned to 17.11; a major-version upgrade (18+) is a manual dump-and-restore, never an image bump.

## Backups and restore

Backups are `pg_dump` custom-format dumps encrypted with AES-256 (OpenSSL, PBKDF2) using `BACKUP_PASSPHRASE`, each with a `.sha256` checksum. They include the auth tables (users, password hashes, sessions), profiles, the operation ledger and the admin role. Take one on demand:

```sh
docker compose -f docker-compose.yml -f docker-compose.accounts.yml exec backup backup.sh --once
```

**Restore rehearsal** (do this after setup and every few months), into a throwaway database that never touches the real one:

```sh
docker network create relic-restore
docker run -d --name restore-pg --network relic-restore -e POSTGRES_DB=relic -e POSTGRES_USER=relic -e POSTGRES_PASSWORD=x postgres:17.11-alpine
# wait a few seconds for it to start, then (use your real passphrase and backup file):
docker run --rm --network relic-restore -v /path/to/backups:/backups \
  -e PGHOST=restore-pg -e PGUSER=relic -e PGPASSWORD=x -e PGDATABASE=relic -e BACKUP_PASSPHRASE='…' \
  --entrypoint restore.sh <backup image name> /backups/daily/relic-YYYYMMDD-HHMMSS.dump.enc
docker exec restore-pg psql -U relic -d relic -c 'select count(*) from game_account; select email, role from "user" where role = '"'"'admin'"'"';'
docker rm -f restore-pg && docker network rm relic-restore
```

On Git Bash for Windows, prefix with `MSYS_NO_PATHCONV=1` so `/backups/...` isn't rewritten. Rehearsed on 2026-10-14 against the test stack: checksum verified, account, verified email, admin role, profile, sessions and operation ledger restored, and an existing player token worked against a server pointed at the restored copy. A wrong passphrase refuses to restore.

**Real recovery** (dead disk, corrupted database): stop `relic-diver`, start an empty `postgres`, run `restore.sh` into it with the newest good backup, then start everything. Progress since that backup is lost; players' unsent run results are kept on their devices and retried.

## Moving to the Ubuntu laptop or a VPS

1. Install Docker on the new host and copy the repository and `.env` (via your password manager, not chat or email).
2. Rehearse: start only `postgres` there, restore the latest backup, check accounts, profiles and the admin role.
3. Announce a short pause. On the old host, stop `relic-diver` (no more writes) and take a final `backup.sh --once`.
4. On the new host, restore that final backup into an empty database, then `up -d` the full stack and check `/healthz`, sign-in and a profile.
5. Point the Cloudflare Tunnel at the new host (or move the tunnel token) and verify from outside.
6. Keep the old host stopped but intact for a week as a rollback. Never run both writable at once, or the two databases split.

Open lobbies end during the switch. Players keep their account progress; the hostname doesn't change, so no game reinstalls are needed.

## Data and privacy notes

- Stored per account: email, password hash (Better Auth), display name, sessions, the game profile, run records and operation ids. No IP addresses or device fingerprints are stored by the game API; Better Auth records the IP and user agent on sessions.
- Players can delete their account (`POST /api/auth/delete-user` with their password); that removes the game account, progress and receipts. A deleted account's backups age out with the 7-daily/4-weekly rotation.
- Logs never contain passwords, tokens or reset links. Verification and reset links go only to email.
