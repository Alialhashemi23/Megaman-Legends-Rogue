# Claude continuation brief — 2026-10-14

## Read first

Repository: `D:\code repos\Megaman-Legends-Rogue` on the owner's Windows PC
(`ALAWIPC`), PowerShell. The earlier C: project path is stale. Read root
`AGENTS.md`, `HANDOFF.md`, `DESIGN.md`, then the relevant subsystem handoffs;
do not rescan backups, dump all scripts or rerun every suite for context.

For this continuation: `docs/handoff/ANDROID.md`, `ACCOUNT-SYNC.md`,
`docs/ANDROID-UPDATES.md` and `docs/ACCOUNT-API.md`. Consult
`docs/handoff/ROADMAP.md` for phase definitions and `docs/ACCOUNTS-OPS.md` only
for operational work. `PHASE4-BRIEF.md` is historical implementation guidance;
phase 4 is already implemented and merged.

## Exact code/deployment split

- `main` and GitHub were synchronized at `5966358` before this docs-only handoff
  commit. Check current `git status`, `git log` and remote state once.
- Phase 4 implementation: `084d6a6`; account operations: `566edfc`.
- Phase 5 implementation: `dec0ddc`. Both feature branches were fast-forwarded
  into `main` with explicit owner approval. No merge conflicts or local edits
  remained before this handoff. Branches remain as history, not pending work.
- **Live:** phase 4 web game + accounts on the local PC, through Cloudflare
  Tunnel at `https://megaman.galosengen.dev`; local origin `127.0.0.1:8080`.
  PostgreSQL and game are healthy, backup is running, migrations exited 0.
  Containers use Compose project `megaman-legends-rogue`.
- **Not live:** phase 5 code, new credits UI, Android download routes/metadata
  and APK publication. Updating `main` did not rebuild/restart the server.
- Tracked web ZIP, Windows pack and portable ZIP match phase 5 source. APKs are
  ignored/local: `build/RelicDiver-android.apk` (ARM64) and
  `build/RelicDiver-android-x86_64.apk` (emulator), versionName `0.18.0`,
  versionCode **3**, test/debug-signed. ARM64 size **33,685,083 bytes**, SHA-256
  `f071e7a47f2ab34c5211892d14662d13a5fac0c0558d352520f66a164dad8638`.
- Protocol **7**, checkpoint **3**, profile **2**, API **v1** unchanged.

## Readiness review and phase 6 — 2026-10-14 (merged into `main`)

Readiness fixes (from `fix/phase45-readiness`): restore failure states, outbox,
background/return, server switching and update cancellation were reviewed.
Fixes in `scripts/account.gd`, `scripts/android_updates.gd`, `scripts/hud.gd`,
tests in `tests/android_checks.gd`. Details in `ANDROID.md`. Reviewed and judged
sound: outbox ordering/idempotent retry, pause persistence, device-code
wall-clock expiry, server-change guard while an account is active, update
metadata validation. Owner checklist: `docs/handoff/RETROID-CHECKLIST.md`.

Both were pushed and **deployed live on 2026-10-14** with explicit owner approval (backup first; migrations applied; owner granted admin). APKs stay local/unpublished. Phase 6 (from `feature/owner-dashboard`, owner-authorized): see
`docs/handoff/OWNER-DASHBOARD.md`. APK build 4 (`0.18.1`) carries both; keep
the build-3 APK (`build/RelicDiver-android-3.apk`) as the "old" install for the
Retroid upgrade test.

## Latest user decision

Keep phase 5's **browser-based APK download flow** for the first Retroid test.
The owner asked about an in-game download progress bar, then agreed to test the
browser flow first and consider the progress bar as later polish. Do not replace
the updater now. Existing metadata, hosting, checksums and packaging can be
reused if a native downloader is requested later. Android still controls install
approval; no automatic install promise.

The owner registered, confirmed their email, and signed in. Database checks
confirmed a verified user, game account/profile and active session. They were
away from the PC and deferred actually playing until home. Their "can't play"
statement was **not established as a game defect**. Phase 6 (owner dashboard)
has not started and is not authorized just by this handoff.

## What phase 5 already does

Android device approval (`relic-android`), bearer calls and account tickets;
AES-256-GCM token encryption using a non-exportable Android Keystore key through
the built-in Java bridge. Ciphertext and key aliases are separated by server
origin, with origin-authenticated encryption; no plaintext token fallback.
Windows remains memory-only. Pause persists pending operations/checkpoints;
device-code expiry counts time in the browser; resume refreshes outside digs.

Startup checks `/updates/android/stable.json` with timeout/size limits, validates
integer build numbers and same-origin HTTPS download URLs, and offers optional
or required-online update choices. Guest solo remains available if metadata is
unavailable. Explicit Download outside a dig/lobby opens `/downloads/android/`.
The app does not claim to verify APK bytes it never reads.

`tools/prepare-android-release.ps1` stages immutable versioned APKs, actual
manifest version, size, SHA-256 and signing fingerprint locally; changed bytes
under an existing version code are refused. `docker-compose.android.yml` is an
opt-in, read-only release-directory mount. Neither runs publication by itself.
The relay's Android minimum-build gate depends on self-reported platform/build;
legacy clients without those fields cannot be reliably identified.

## Completed validation — reuse this evidence

- Android client **44** checks; account client **34**; UI **47**.
- Node Android update + relay tests: **10**, all passed.
- Reproducible `tools/test-android-vault.ps1`: unique disposable app, first run
  **8/0**, process restart **9/0**, higher-code upgrade **9/0**. Covers encryption,
  decryption, origin isolation, no plaintext file, tamper rejection and sign-out.
- Full emulator APK startup passed; game code 2 → 3 upgrade preserved the
  existing Guest archive's SHA-256 exactly.
- Wrong-key test upgrade rejected by Android (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).
- Local staging refused different APK bytes under an existing code.
- Phase 4's wider regression and real API/browser/Windows tests are already
  recorded in `ACCOUNT-SYNC.md`; do not rerun them all unless a relevant change
  or failure warrants it.

Native bridge details that were emulator-verified: `KeyStore.load(null)` uses
the one-argument overload; `getKey(alias, PackedByteArray())`; nested builder
constructor is called as `KeyGenParameterSpec$Builder`. Do not revert these to
Java examples without checking the actual Godot bridge behavior.

## Sensible next work

Review remaining phase 4/5 readiness and make focused fixes on a new branch from
`main` if needed. Pay attention to startup restoration failure states (invalid
profile/cache write failure), outbox persistence, browser background/return,
server switching, and update cancellation; test only meaningful affected paths.
Do not assume happy-path checks establish every failure case.

Prepare/maintain the owner's concise Retroid checklist: device approval and
return to game; restart retaining sign-in; one earned result/purchase appearing
on browser and Windows; controller/Back navigation; sleep/reconnect; update over
the existing app retaining progress/settings/account access. Real Retroid
cross-play, frame pacing, heat, battery and installer no-space/cancel/sleep
scenarios remain unverified. Emulator evidence is not hardware acceptance.

Production signing/key backup and owner-approved publication are still needed
before a public Android update promise. Use the same app id and signing key,
increase versionCode for distributed updates, never require uninstalling.

## Operational constraints and traps

- Don't deploy/restart services, publish APKs/releases, provision services or
  spend money without a fresh owner request. Prior approvals were fulfilled;
  this handoff is not a new deployment request. Push authorized source work only
  to `https://github.com/Alialhashemi23/Megaman-Legends-Rogue`.
- No subagents unless the owner asks. Preserve personal saves and the original
  PS1 look/music, separate Guest/account storage, and run-reset rules.
- `.env` contains existing tunnel, database/auth/backup and Resend credentials.
  Never print, commit, package or paste it. The game uses a separate sending-only
  SMTP key; an earlier management key was exposed in chat and should be rotated
  by the owner independently, without breaking the game key.
- Resend `mail.galosengen.dev` is verified; DNS setup is finished. No need to
  repeat Cloudflare login or create another mail domain.
- Encrypted daily backups: the synced folder in `.env` `BACKUP_HOST_DIR`,
  7 daily + 4 weekly; isolated restore passed. Human confirmation of OneDrive
  off-machine syncing and a separate password-manager recovery-secret copy
  remains. Never run `docker compose down -v` on the live stack.
- Ignored `.env` `COMPOSE_FILE` selects base + accounts files, keeping accounts
  enabled under default Compose commands. The Android add-on is not selected.
- Ignored `tools/accounts-setup/` has local setup/verification helpers; don't
  rerun provisioning scripts. Temporary `tools/keydrop/` helpers are inactive;
  old key-entry endpoints were removed. Don't reactivate them.
- Test settings use `APPDATA`/`LOCALAPPDATA=tools/runtime`. Exporting with those
  settings fails unless templates are linked there: run packaging in a fresh
  shell using installed templates. Android packaging manages its own settings
  under `D:/Android/godot-config`. Godot export restarts ADB; use
  `adb wait-for-device` before installing. SDK/JDK/emulator are under `D:/Android`.
- D: Git/network/Docker operations may require the environment's normal approval
  mechanism; a sandbox Git "must be run in a work tree" error was resolved by
  using authorized elevated execution, not by recreating `.git`.
- Raw licenses in `assets/notices/credits.txt` preserve upstream text, including
  two trailing-space lines. Don't treat that as a runtime failure or rewrite
  license terms. Engine/assets/license exceptions remain intact.

After meaningful source changes, update the relevant handoff and refresh web +
Windows artifacts together (`tools/package-web.ps1`, Windows export-pack,
`tools/package-windows.ps1`); refresh Android APKs when Android code changes.
Don't silently publish those artifacts or change the live deployment.
