# Technical handoff

## Runtime and architecture

Godot 4.7.1, GDScript, GL Compatibility renderer, GodotPhysics3D. Entry point: project.godot → main.tscn. Solo play needs no accounts, network access, Blender, FluidSynth or Python. Online co-op connects to the lobby server in `server/` (see NETWORK.md). Native Godot audio is the runtime sound engine; the web export keeps the full mixer (`audio/general/default_playback_type.web = Stream`).

| File | Responsibility |
|---|---|
| scripts/game.gd | Generation, encounters, run state, rewards, saves and built-in validation modes; the online co-op rules are at the end |
| scripts/progression.gd | Zenny rewards, the per-digger skill trees (costs, prerequisites, effects), profile v2 migration and checksummed save codes |
| scripts/account.gd | Browser/Windows auth, account profiles, durable ordered outbox, HTTP/retries, device codes, run leases, migration and lobby tickets (ACCOUNT-SYNC.md) |
| scripts/player.gd | CharacterBody3D movement, camera collision, aiming, lock-on, signature attacks, statistics and footsteps |
| scripts/character.gd | `DiverCharacter`: imported rigs (`COUNT`, `IDS`, per-character buster colour/scale), manual animation advance, aim layer and muzzle |
| scripts/enemy.gd | Robot behavior, attack preparation/recovery, guardians and damage |
| scripts/ruins.gd | Floor planning (rooms on a 40 m cell grid, passages, corridor links, loops, layouts) and construction of rooms, walls, corridors, raised blocks and ramps |
| scripts/navigation.gd | 1 m traversable grid built from room rectangles and corridor links; cover and raised stonework are solid except `game.nav_open` (platform tops, ramp centre lines) |
| scripts/bolt.gd | Swept projectile collisions, splash obstruction and arcing bombs |
| scripts/hud.gd | Scaled UI, menus (`MENU_MODES`), Workshop, save codes, equipment, map and input targets |
| scripts/sound.gd | Audio buses, voices, crossfades, settings and ambience |
| scripts/art.gd | Environment/robot construction, materials, floor-tile MultiMesh and historical procedural character code |
| scripts/paths.gd | `DiverPaths`: picks portable `save/` or sandboxed `user://` storage per platform |
| scripts/net.gd | Online transport, identity, lobby state, reconnect loop and invite links |
| scripts/settings.gd | Options and the InputMap: rebindable keyboard/controller actions, prompts, rumble, display (settings.json) |
| server/ | Node web host and lobby relay for the browser build (NETWORK.md) |
| server/accounts/ | Optional accounts: Better Auth config, PostgreSQL schema, progress store, `/api/v1` routes, account pages, and `rules.js` (a server copy of the progression rules) |

## Floors and tuning knobs

- **Rooms** (`scripts/ruins.gd`) carry `kind`, `half`, `cells`, `height` and `layout`: 0–4 cover arrangements, 5 Stepped Vault, 6 Terrace Hall, 7 Grand Concourse, 8 passage. `game.links` are the corridors; `game.platforms` feeds `floor_height()`. Robots chase directly only on the same level as their target and otherwise path, including up ramps.
- **Difficulty** lives in `scripts/enemy.gd`: `hit(base, per_floor)` for damage, `pace()` for wind-up and recovery length, `lock_aim()` for sentry and guardian shots that lead the target, `shield` for the guardian's overdrive guard, Life in `_ready`. Hostile bolt speed is in `bolt.gd`. These are first-pass numbers awaiting a playtest.
- **Progression:** the Zenny formula, node costs and tree bonuses are in `scripts/progression.gd`; part unlock gates are the `unlock` fields of `ITEMS` in `scripts/game.gd` (legacy gates in `progression.gd` `OLD_GATES`).
- **Performance:** each room's floor tiles are one MultiMesh (`DiverArt.tiles`); hit-flash and damage-number shaders are pre-warmed in `warm_hit_effects` to avoid a first-hit stall in the browser.

## Setup and launch

On the original PC, Play.cmd and Edit.cmd use the bundled engine in tools/. On a fresh clone, tools/setup-runtime.ps1 extracts the committed Windows bundle and prepares that engine; Play.cmd and Edit.cmd call it if needed. The portable archive is build/RelicDiver-Windows.zip. It contains the executable, content pack and notices. Extract the whole archive before running RelicDiver.exe. The large loose executables remain ignored.

For another operating system, use a compatible Godot editor and open project.godot. Asset imports regenerate .godot automatically. Do not copy another machine's import cache.

## Persistence precautions

| Data | Desktop (source) | Web / Android (`user://`) |
|---|---|---|
| Progress profile | `save/archive.json` | `user://archive.json` (IndexedDB) + localStorage recovery mirror |
| Settings and controls | `save/settings.json` | `user://settings.json` |
| Audio settings | `save/audio.json` | `user://audio.json` |
| Online identity | `save/online.json` | `user://online.json` |
| Active online dig | `save/run_checkpoint.dat` | `user://run_checkpoint.dat` |

The portable build keeps its own `build/save/` (or the extracted bundle's `save/`); it is a separate profile. Preserve existing profiles and never commit them. Desktop paths are `res://save/...`, which is read-only inside an Android APK, so `DiverPaths.pick()` (`scripts/paths.gd`) sends web and Android to `user://` (see [ANDROID.md](ANDROID.md)).

Progress saves atomically on every Workshop purchase and at the end of each run; discoveries are recorded when parts are fitted. Online digs checkpoint every 5 s and on build changes; finishing a run deletes the checkpoint. Solo digs are not checkpointed (`solo_checkpoints = false`).

Tests and captures must use isolated save paths (`--checkpoint-path=`, `checkpoint_path`, `save_path`). `game.smoke_test` suppresses both saving and sound. To capture sound, leave it false and set `game.save_path` and `sound.settings_path` to test-only locations before events that write.

## Verification and export

PowerShell on the original PC:

```powershell
$env:APPDATA = Join-Path (Get-Location) 'tools/runtime'
$env:LOCALAPPDATA = $env:APPDATA
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --editor --path . --import
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tests/character_checks.gd
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --movement-test
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --export-pack 'Windows Desktop' build/RelicDiver.pck
```

| Area | Checks |
|---|---|
| Characters, motion, aim | `tests/character_checks.gd` |
| Combat, robots, obstruction | `tests/combat_checks.gd`, `--combat-test` |
| Movement and traversal | `--movement-test` |
| UI and menus | `tests/ui_checks.gd`, renders via `tests/ui_preview.gd` |
| Controls and Options | `tests/options_checks.gd` (simulated controller), renders via `tests/options_preview.gd` |
| Audio | `tests/audio_checks.gd` |
| Guardian milestones | `tests/milestone_checks.gd` |
| Progression, Workshop, save codes | `tests/progression_checks.gd`, `--persistence-test`; browser: `tests/web_progression.mjs` |
| Co-op map and part picks | `tests/coop_feedback_checks.gd`, renders via `tests/coop_feedback_preview.gd` |
| Accounts server | `server/` `npm test` runs `rules.test.js` always and `accounts.test.js` when `TEST_DATABASE_URL` points at a PostgreSQL server (see the file header for a one-line Docker command) |
| Online and checkpoints | `server/` `npm test`, `tests/run_resume_checks.gd`, `tests/net_test.sh <godot>` (Git Bash), `tests/web_e2e.mjs`, renders via `tests/coop_preview.gd` (see NETWORK.md) |
| Whole loop | `--smoke-test` |

Run only the checks relevant to a change. Latest full results are in [../FEATURE-REPORT.md](../FEATURE-REPORT.md). After gameplay changes, refresh the web bundle with `tools/package-web.ps1` (or `.sh`) and the Windows ZIP with `tools/package-windows.ps1`.

Export filters omit tools, tests, backups, screenshots and saves, while retaining required asset/font notices. Refresh build docs and recreate the portable ZIP after shipping a changed pack; never replace an existing user's save folder as part of rebuilding. The full editor executable currently acts as the portable runtime, making the bundle larger than a normal release-template export.
