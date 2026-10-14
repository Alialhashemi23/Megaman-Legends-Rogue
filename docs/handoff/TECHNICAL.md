# Technical handoff

## Runtime and architecture

Godot 4.7.1, GDScript, GL Compatibility renderer, GodotPhysics3D. Entry point: project.godot → main.tscn. Solo play needs no accounts, network access, Blender, FluidSynth or Python. Online co-op connects to the lobby server in `server/` (see NETWORK.md). Native Godot audio is the runtime sound engine; the web export keeps the full mixer (`audio/general/default_playback_type.web = Stream`).

| File | Responsibility |
|---|---|
| scripts/game.gd | Generation, encounters, run state, rewards, progression, saves and built-in validation modes |
| scripts/player.gd | CharacterBody3D movement, camera collision, aiming, lock-on, busters, statistics and footsteps |
| scripts/character.gd | Imported character scenes, manual animation advance, aim layer and muzzle attachment |
| scripts/enemy.gd | Robot behavior, attack preparation/recovery, guardians and damage |
| scripts/ruins.gd | Floor planning (rooms on a 40 m cell grid, passages, corridor links, loops, layouts) and construction of rooms, walls, corridors, raised blocks and ramps |
| scripts/navigation.gd | 1 m traversable grid built from room rectangles and corridor links; cover and raised stonework are solid except `game.nav_open` (platform tops, ramp centre lines) |
| scripts/bolt.gd | Swept projectile collisions and splash obstruction |
| scripts/hud.gd | Scaled UI, menus, equipment, map and input targets |
| scripts/sound.gd | Audio buses, voices, crossfades, settings and ambience |
| scripts/art.gd | Environment/robot construction, materials and historical procedural character code |
| scripts/net.gd | Online transport, lobby state, invite links (co-op rules live at the end of game.gd) |
| scripts/settings.gd | Options and the InputMap: rebindable keyboard/controller actions, prompts, rumble, display (settings.json) |
| server/ | Node web host and lobby relay for the browser build (NETWORK.md) |

## Setup and launch

On the original PC, Play.cmd and Edit.cmd use the bundled engine in tools/. On a fresh clone, tools/setup-runtime.ps1 extracts the committed Windows bundle and prepares that engine; Play.cmd and Edit.cmd call it if needed. The portable archive is build/RelicDiver-Windows.zip. It contains the executable, content pack and notices. Extract the whole archive before running RelicDiver.exe. The large loose executables remain ignored.

For another operating system, use a compatible Godot editor and open project.godot. Asset imports regenerate .godot automatically. Do not copy another machine's import cache.

## Persistence precautions

Source profiles are save/archive.json and save/audio.json. Portable profiles are build/save/ (or the extracted bundle's save/). They are separate. Preserve existing profiles, and never commit them. Runs in progress are checkpointed to `save/run_checkpoint.dat` (web: `user://run_checkpoint.dat`) and resumed with Continue/Rejoin Dig; finishing a run deletes it. Tests pass isolated `--checkpoint-path=` or set `checkpoint_path`. Progress records are written on completed/ended runs; discoveries are recorded when parts are fitted.

Tests and captures must use isolated save paths. game.smoke_test suppresses both saving and sound. To capture sound, leave it false and set game.save_path and sound.settings_path to test-only locations before events that write.

## Verification and export

PowerShell on the original PC:

```powershell
$env:APPDATA = Join-Path (Get-Location) 'tools/runtime'
$env:LOCALAPPDATA = $env:APPDATA
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --editor --path . --import
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tests/character_checks.gd
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tests/combat_checks.gd
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --movement-test
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --export-pack 'Windows Desktop' build/RelicDiver.pck
```

Use only relevant checks after changes. Other suites: tests/ui_checks.gd, tests/audio_checks.gd; built-in --smoke-test, --combat-test and --persistence-test. Controls/options: `tests/options_checks.gd` (simulated controller input) and `tests/options_preview.gd` (renders). Online and persistence: `server/` npm test, `tests/run_resume_checks.gd`, `tests/net_test.sh <godot>`, `tests/web_e2e.mjs` and `tests/coop_preview.gd` (see NETWORK.md). After gameplay changes, also refresh the web bundle with tools/package-web.ps1 or tools/package-web.sh. Latest motion pass: character 3868/0 failures, combat 3207/0, movement traversal passed in source and packed game, export and GPU launch passed. Earlier UI/audio suites passed before that animation-only change.

Export filters omit tools, tests, backups, screenshots and saves, while retaining required asset/font notices. Refresh build docs and recreate the portable ZIP after shipping a changed pack; never replace an existing user's save folder as part of rebuilding. The full editor executable currently acts as the portable runtime, making the bundle larger than a normal release-template export.
