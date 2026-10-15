# Relic Diver handoff

Current state of the project for a new session. Updated 2026-10-14. Game direction is in [DESIGN.md](DESIGN.md); what's next is in [docs/handoff/ROADMAP.md](docs/handoff/ROADMAP.md); build history is in [CHANGELOG.md](CHANGELOG.md).

**Current continuation brief:** [docs/handoff/CLAUDE-NEXT.md](docs/handoff/CLAUDE-NEXT.md) records the exact merged/live split, completed validation, operational traps and the owner's latest decision to test the browser updater before considering an in-game progress bar.

## Status

- **Roadmap phase 1 (co-op map sharing, waiting part picks, cache icons)** is merged and deployed (CHANGELOG 17).
- **Roadmap phase 2 (Android)** is merged: the APK builds with `tools/package-android.ps1` and runs on the emulator; the Retroid is untested. See [docs/handoff/ANDROID.md](docs/handoff/ANDROID.md).
- **Roadmap phase 4 (game account sync)** is merged into `main` through `dec0ddc` (implementation `084d6a6`) and deployed to the local Docker server on 2026-10-14. Accounts are now enabled with PostgreSQL, verified Resend SMTP and encrypted daily backups, explicitly authorized by the user. Public account routes and an isolated backup restore passed. See [docs/handoff/ACCOUNT-SYNC.md](docs/handoff/ACCOUNT-SYNC.md).
- **Roadmap phase 5 (Android accounts and updates)** is merged into `main` through `dec0ddc`, including phase 4. Android Keystore encryption/recovery passed emulator process-death and in-place-upgrade checks; update metadata, relay compatibility and client checks passed. APK build 3 (`0.18.0`) is test-signed locally; nothing published or deployed. Real Retroid account/cross-play and installer failure tests remain. See [docs/handoff/ANDROID.md](docs/handoff/ANDROID.md).
- **Phase 4/5 readiness fixes** (offline Guest keeps the saved Android session, offline restores retry, invalid restored profiles stay unconfirmed, update-browser failures keep the prompt) and **roadmap phase 6 (read-only owner dashboard)** are merged into `main` and **deployed live** (2026-10-14, owner-approved; backup taken first, migrations `twoFactor` + `002_owner_dashboard` applied, owner account granted admin): authenticator-protected `/admin`, login/dig/activity events with 30/90/366-day retention, and the game's play-time reports. See [docs/handoff/OWNER-DASHBOARD.md](docs/handoff/OWNER-DASHBOARD.md). Retroid checklist: [docs/handoff/RETROID-CHECKLIST.md](docs/handoff/RETROID-CHECKLIST.md).
- **Roadmap phase 3 (accounts backend)** is merged into `main` and **off unless configured**: Better Auth + PostgreSQL, the `/api/v1` progress API, device-code sign-in and lobby tickets. Contract [docs/ACCOUNT-API.md](docs/ACCOUNT-API.md); running it [docs/ACCOUNTS-OPS.md](docs/ACCOUNTS-OPS.md). Phase 4 integrates the client without changing v1.
- **Shipped (through pass 16):** a complete three-descent roguelike loop; four playable diggers (Mega, Roll, Tron, Servbot) with signature attacks; Zenny and per-digger Workshop skill trees; versioned local progress with save codes; browser play and online co-op for up to four with host migration, reconnects and checkpoints; controller support, Options and rebinding; bigger varied ruins and a to-scale map. Details: [docs/FEATURE-REPORT.md](docs/FEATURE-REPORT.md).
- **Compatibility numbers:** game protocol `NET_VERSION` 7 (`scripts/net.gd`), `CHECKPOINT_VERSION` 3 (`scripts/game.gd`), profile `VERSION` 2 (`scripts/progression.gd`). All co-op players must run the same protocol.
- **Next:** owner account/email confirmation is complete. Owner still needs to playtest phase 4 and Android phase 5 on the Retroid; keep recovery secrets in an off-machine password manager and confirm OneDrive backup syncing. Phases 4/5 are merged; owner dashboard (phase 6) follows. Future deployments still need authorization.
- **Latest owner playtest (2026-10-14):** game is good; requested an FFX Sphere Grid–style skill grid, Workshop focus fix, Credits/Dig Record overlap fix, accurate sign-in button state, and removing save codes. Details and open questions: [docs/handoff/PLAYTEST-FEEDBACK-2026-10-14.md](docs/handoff/PLAYTEST-FEEDBACK-2026-10-14.md). Not implemented yet.
- **Still needed from humans:** a real playtest of balance (difficulty is the first-pass tuning from CHANGELOG entry 14, the Workshop numbers are provisional, co-op party scaling is a first guess) and a browser start-to-finish run of the newest content.

## User intent and constraints

A non-profit Mega Man Legends fan roguelike: colorful ancient machinery, mysterious robots, dungeon exploration, third-person free aim with optional lock-on, buster combat, Risk of Rain-style stackable parts. Run power resets; unlocks and Workshop purchases persist. Keep the original PS1 look and compact, springy motion (see DESIGN.md).

- **Repository:** the user authorized https://github.com/Alialhashemi23/Megaman-Legends-Rogue (default branch `main`). Commit and push there; don't publish releases or push elsewhere without a request.
- **Hosting:** the user hosts the game themselves and does the deploying. The repo ships the server, Docker Compose and tunnel configuration. Don't redeploy the live site, provision services or spend money unless asked.
- **Never commit or package:** `.env`, tunnel tokens, personal saves, import caches, backups, raw captures or loose engine executables (and, once the roadmap lands, databases, auth secrets and signing keys).
- **Saves:** preserve the user's profiles. Tests and previews use isolated paths.
- **Working style:** work autonomously within the requested scope; no subagents unless asked; run checks relevant to the change, not every suite; keep handoffs current.

## Location and launch

- Repository: `D:\code repos\Megaman-Legends-Rogue` on the user's Windows PC. Shell: PowerShell (Git Bash available).
- Engine: Godot 4.7.1, `tools/Godot_v4.7.1-stable_win64_console.exe` (GUI editor alongside; both ignored by Git and restored from `build/RelicDiver-Windows.zip` by `tools/setup-runtime.ps1`). Web export templates are installed under `%APPDATA%\Godot\export_templates\4.7.1.stable`. If a script reports an undeclared `Diver*` class, the local `.godot` class cache is stale: run the `--headless --editor --import` step in TECHNICAL.md. The Android toolchain (JDK 17, SDK, NDK, templates) is under `D:\Android`.
- `Play.cmd` runs the source project; `Edit.cmd` opens the editor. Portable build: `build/RelicDiver.exe` + `RelicDiver.pck`.
- For tool and test runs set `APPDATA` and `LOCALAPPDATA` to the workspace's `tools/runtime`. Python with NumPy is needed only for the character converter; FFmpeg only for videos.
- Node 22 and Docker are installed. Commands and suites: [docs/handoff/TECHNICAL.md](docs/handoff/TECHNICAL.md).

## Live deployment

https://megaman.galosengen.dev is served from this PC through a Cloudflare Tunnel by `docker compose`. Accounts add `postgres`, a completed `migrate` job and `backup` to `relic-diver` and `cloudflared`; secrets are in the untracked `.env`. Its `COMPOSE_FILE` includes both Compose files so default commands retain accounts. Encrypted backups go to `C:/Users/Temp/OneDrive/Documents/RelicDiver-Account-Backups`; off-machine sync and a separate recovery-secret copy still need human confirmation. The tunnel routes to `http://relic-diver:8080`; the desktop build's default server is `wss://megaman.galosengen.dev/ws`. A move to the user's Ubuntu laptop and later a VPS is planned as part of the roadmap.

To ship a gameplay change (only when the user asks to deploy, because a restart drops online lobbies):

```powershell
.\tools\package-web.ps1
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --export-pack 'Windows Desktop' build/RelicDiver.pck
.\tools\package-windows.ps1
docker compose up -d --build relic-diver
```

Then check `https://megaman.galosengen.dev/healthz` and that the site's `index.pck` matches `build\web\index.pck` in size. Hosting guide: [docs/ONLINE.md](docs/ONLINE.md).

## Where to read next

| Task | Read |
|---|---|
| Any roadmap feature | [ROADMAP.md](docs/handoff/ROADMAP.md) |
| Game systems, checks, exports | [TECHNICAL.md](docs/handoff/TECHNICAL.md) |
| Online co-op, server, web build | [NETWORK.md](docs/handoff/NETWORK.md) |
| Accounts API, account server operations | [ACCOUNT-API.md](docs/ACCOUNT-API.md), [ACCOUNTS-OPS.md](docs/ACCOUNTS-OPS.md) |
| Android APK, toolchain, emulator | [ANDROID.md](docs/handoff/ANDROID.md) |
| Owner dashboard, admin MFA, analytics | [OWNER-DASHBOARD.md](docs/handoff/OWNER-DASHBOARD.md) |
| Models, animation, aiming | [ART-ANIMATION.md](docs/handoff/ART-ANIMATION.md) |
| Menus, sound, music, videos | [AUDIO-UI.md](docs/handoff/AUDIO-UI.md) |
| Tracked files, packaging, licensing | [REPOSITORY.md](docs/handoff/REPOSITORY.md) |
| Balance and playtest feedback | [PLAYTEST-ROADMAP.md](docs/handoff/PLAYTEST-ROADMAP.md) |

Read only what the task needs. Don't rescan backups, dump whole scripts, rerun every suite or redo completed work to establish context. Check `git status` / `git log` for the exact repository state.
