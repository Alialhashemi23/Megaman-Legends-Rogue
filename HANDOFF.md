# Relic Diver handoff

## In-game sign-in + Guest rule — 2026-10-16 (build 30, Android code 5)

Owner report: the title didn't show GALOSENGEN after signing in, and Android
looked like a fresh slate. Read-only diagnosis: a single account; Android (old
APK 4) synced to it; the browser hadn't been signed in since Oct 14, so the
owner's playtesting since then lived in that browser's Guest save. The owner
asked for (1) an in-game modal for sign-in on every platform and (2) Guest
progress moving into a new or empty account, while an account that already has
progress wins and Guest is discarded. Both are implemented; see the top of
ACCOUNT-SYNC.md. The owner's account has an authenticator, so the modal has a
code step. Android APK code 5 / 0.19.0 (same test key as code 3/4, verified
with apksigner) is at `build/RelicDiver-android.apk`; it must be installed on
the Retroid by hand while USB debugging is off. The server and protocol are
unchanged (device endpoints remain for old APKs).

## Polish P7 animation and movement — 2026-10-16 (build 29)

Dash: the old dash was invisible because its 0.12 s blend left the static pose
on screen for about 0.07 s of the 0.19 s dash, the pose leaned back, and dash
i-frames blinked the model. Now `character.gd` plays one-shot `dash`,
`dash_back`, `dash_left`, `dash_right` clips (0.36 s: onset, travel, plant at
0.24 s, settle) from the dash's first frame, picked by `dash_direction`
(relative to facing, from `player.facing_relative()`; remotes use synced
velocity). The recovery plays unless the digger moves, jumps or is hit.
`player.dash_guard` holds dash i-frames separately from `invincible` (no blink);
`dash_dust()` draws a ring at onset (no RNG).

Legs: the converter's `planted()` solves run/backpedal legs with two-bone IK onto
a foot path whose stance sweep matches `RUN_SPEED` 6.2 (player `base_speed`),
with heel/toe roll, a swing arc and an airborne moment; body height is capped so
planted boots reach the floor. Rigs without knees (Servbot) keep FK. Run lean
sign fixed (+X on Hips leans back). New `land` clip after > 0.3 s airborne when
standing still. Cadence scales with stick tilt (0.55–1).
Protocol, checkpoint and profile unchanged. Not done: strafes still skate
(sideways planting would cross the legs), and per-digger personality beyond the
existing differences is waiting for the owner's direction. Details in ART-ANIMATION.md.
Packaging note: run `tools/package-web.ps1` and the pack export with the normal
`%APPDATA%`. `tools/runtime/Godot/export_templates` is empty, so the test-time
APPDATA override makes the Web preset fail with "configuration errors".

## Polish P6 guardian milestones — 2026-10-15 (build 28)

`game.MILESTONES` (10 entries with icon/affinity/desc) and `MILESTONE_DEPTHS = [1, 2]`.
Each client grants its own milestone from `_process` once `guardian_dead` is set
on a milestone descent (`milestone_owed_or_taken()` dedupes against taken, open
and pending picks), so no new network message is needed. A grant opens a choice
straight away in play, otherwise it waits as a pending pick. `milestone_offer()`
weights the three picks by fitted affinity parts with an RNG seeded by run id,
descent, player id and character, so it never touches gameplay RNG. Picks reuse
the relic choice flow with `choice_kind == "milestone"` (`clean_pending()`
validates both kinds), and they can be deferred online.
`player.milestones/milestone_depths/second_wind_depth` ride in builds (`clean_milestones()`).

Effects are host-side in `enemy.take_damage()`/`die()` for Arc, Wildfire,
Fortune, Salvo and Scavenger, and in `player.gd` for Bulwark, Second Wind,
Kinetic, Glacier and Twin. Final-guardian decision: no milestone, because the
dig ends there. Protocol 10. `tests/milestone_checks.gd`; `tests/net_driver.gd`
now checks that host and guest each get their own milestone. Deployed from `31a36e2`
(container healthy; local and public `index.pck` match the export; live boot checked). Next phase: P7
(dash animation first).

## Polish P5 specializations — 2026-10-15 (build 27)

`DiverProgression.SPECS` holds two specializations per digger, keyed by the grid
nodes `spec_a` (linked from Quick Loader) and `spec_b` (from Signature II).
Equipping is per device (`DiverSettings.specs`), via `game.equip_spec()` (refused
during a dig) and `equipped_spec()`. A dig's `player.spec` goes into
`build_state()` / `apply_build()` / proxy info (`clean_spec()` rejects unowned
specializations). `DiverPlayer.specialization()` returns the effect key only when
the equipped node is owned. The effects are:

- Focus Lens and Needle Storm exposure: host-side in `enemy.take_damage()`.
- Ricochet Coil, Siege Breaker, Wide Barrage and Demolition Charge: in `bolt.gd`.
- Storm heat, Field Medic and the Scrap Runner dash bomb: in `player.gd`.
- Scrap Runner's extra scrap: in `enemy.die()`.

Profile 4, protocol 9; the `M_FROST` message now carries a radius. Guardian
build milestones are P6.

## Polish P4 Workshop grids — 2026-10-15 (build 26)

`DiverProgression.NODES/LINKS/START` define one 12-circuit grid layout per
digger (profile 3). A node is buyable when linked to an owned node; a tree is
valid when connected through `frame`. The original five ids keep their effects,
so v2 trees validate unchanged. New effects live in `player.gd` (Life, damage,
attack speed, dash, protection, signature II), `bolt.gd` (blast radius) and
`game.gd` (pickup reach). The server mirror is in `server/accounts/rules.js`;
`server/test/rules.test.js` parses the GDScript and fails on drift. NET_VERSION
is 8. The UI is `hud.gd` `draw_grid()` / `workshop_navigate()` / `grid_step()`.

Specializations (P5) should attach to the grid's branch ends (Quick Loader and
Signature II sides) as new linked nodes, plus the per-dig equip selection.
Old Android APKs (protocol 7, profile 2) cannot read v3 account profiles or
join new lobbies until rebuilt. Prices and values are tuning proposals.

## Polish P3 music — 2026-10-15 (owner-approved; build 25)

All seven cues were re-arranged around their unchanged melodies: per-cue
grooves, voice-led chords, moving bass, call-and-response, harmony lines,
section dynamics and fuller stingers. Loudness matches the old cues. Audio
checks, the data validator and the melody-identity check pass. The owner
listened and approved. Details are in AUDIO-UI.md and
`assets/audio/AUDIO-NOTES.md`. Next phase: P4.

## Polish P1 UI + P2 ruins — 2026-10-15 (tested; build 23)

Verified and shipped per [CLAUDE-POLISH-TEST.md](docs/handoff/CLAUDE-POLISH-TEST.md)
after the owner lifted the no-testing restriction. `scripts/hud.gd`: Workshop
focus/digger switching, Credits position, account-state wording. `scripts/ruins.gd`,
`scripts/art.gd` and nine painted SVGs: per-descent palettes, batched wall/fixture
markings and room crests. Details are in AUDIO-UI.md and ART-ANIMATION.md.

Validated: the SVGs import cleanly; UI/options/account/progression (8 new
Workshop/account checks)/character/combat/resume checks pass; movement,
persistence and smoke tests pass. Seeded layouts, RNG state, colliders,
interactables and enemies match the previous commit exactly (4 seeds × 3
descents). Native draw calls are about 15% lower with frame time no worse. Rooms
from all three descents, plus the title/Workshop at 1440×900 and 960×600, were
rendered and reviewed.

Deployed 2026-10-15 from commit `f175fe1` with `docker compose up -d --build
relic-diver` (default `.env` overlays; Postgres, backups and tunnel untouched;
migrations exited 0). The container is healthy. Local and public `/healthz` return
200, and the served `index.pck` SHA-256 `187f0a5a…a7983d` matches the export.
The live site booted to the new title and a solo B1 dig in a browser. The
Playwright two-browser lobby/rejoin e2e was not run because Playwright is not
installed on this PC.

Test isolation fix: `game._ready()` used to replace a `save_path`/`checkpoint_path`
that a test set before adding the game (a regression since the Android build),
so progression checks wrote their fixture into the desktop `save/archive.json`.
It now keeps pre-assigned paths. On 2026-10-15 that file contained the fixture
(1234 Zenny); its earlier contents are unknown.

Still pending: the owner's visual sign-off on the ruins, browser frame-time
measurement, real Retroid checks, and an Android APK rebuild. The APK is still
code 4 and lacks these visual changes, which are cosmetic only; protocol,
checkpoint and profile are unchanged. Dash animation (P7) is not addressed.

## Latest polish roadmap and deployment authorization — 2026-10-15

The owner completed a design questionnaire in Codex. See
[POLISH-ROADMAP.md](docs/handoff/POLISH-ROADMAP.md) for phases P0–P7 and
[POLISH-PROGRESSION.md](docs/handoff/POLISH-PROGRESSION.md) for the accepted
per-character, fully unlockable Sphere Grids, guardian build milestones, faithful
PS1 ruins, and music polish. Existing melodies are liked; the owner rates current
music at roughly 50% of the desired quality and wants significant refinement.
P1 and P2 are now tested and shipped as build 23 (see above).

The owner explicitly authorizes updating this hosting checkout, pushing GitHub
`main`, and deploying each completed implementation phase to the existing local
container behind `megaman.galosengen.dev`, followed by a short explanation.
This supersedes earlier "future deployments need authorization" / "user deploys"
wording for these phases. Preserve account Compose overlays, database volumes,
secrets, backups, tunnel and concurrent work; follow the roadmap shipping steps.
The new P0–P8 labels are separate from the earlier account/Android phases below.

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
