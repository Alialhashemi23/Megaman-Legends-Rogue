# Relic Diver handoff — 2026-10-13

## User intent and constraints

Continue this existing local Godot project. It is a non-profit Mega Man Legends fan roguelike: colorful ancient machinery, mysterious robots, dungeon exploration, third-person free aim with optional lock-on, buster combat, and Risk of Rain-style stackable themed drops. Unlock items/weapons between runs; run power resets.

Keep the presentation and animation close to the original PS1 Legends: painted textures, original character proportions, compact springy motion, responsive controls, restrained sway. Mega is helmet-off with brown hair and blue armor. Roll is also playable. The user disliked the former blocky procedural character and stiff marching animation.

**Updated authorization:** The user subsequently requested committing this complete project and its design/handoffs to https://github.com/Alialhashemi23/Megaman-Legends-Rogue. This supersedes the earlier no-repository preference for that destination. Do not deploy, publish releases, upload personal saves or publish elsewhere without a request. Local HTTP preview is bound to 127.0.0.1 only. No subagents unless the user asks. Proceed autonomously on authorized changes; avoid repeated confirmations.

Design intent is in DESIGN.md. Subsystem handoffs and a fresh-instance prompt are indexed in docs/handoff/README.md. Repository packaging and exclusions are explained in docs/handoff/REPOSITORY.md.

## Location and launch

Workspace: `C:\Users\Temp\Documents\Codex\2026-10-13\hey-i-want-to-build-a`

- `Play.cmd` launches source; `Edit.cmd` opens the bundled editor.
- Portable game: `build/RelicDiver.exe` with adjacent `RelicDiver.pck`.
- Fresh clone: Play.cmd/Edit.cmd set up the engine from the tracked `build/RelicDiver-Windows.zip`. Loose engine executables, caches, captures and personal saves are ignored; editable models, original ZIPs, audio sources and notices are tracked.
- Engine: `tools/Godot_v4.7.1-stable_win64_console.exe` (GUI executable also bundled).
- PowerShell. Set APPDATA and LOCALAPPDATA to workspace `tools/runtime` for tool/test runs.
- Python: `C:\Users\Temp\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`; NumPy installed. FFmpeg/ffprobe in PATH.

## Implemented

Complete playable three-descent loop, seeded branching rooms, five cover arrangements, robot navigation and telegraphed attacks, three guardians with different attack mixes, three busters, thirteen stackable parts, XP, scrap, caches, healing, unlocks and local records. Console-inspired cobalt/cream/yellow menus, Life gauges, custom icons and bundled fonts. Seven original music cues rendered locally using GeneralUser GS/FluidSynth, 29 effects, ambience, buses, crossfades and sound settings.

Source saves: `save/archive.json`, `save/audio.json`. Portable saves: `build/save/`. Preserve them. Preview/test scripts use isolated paths; `game.smoke_test` suppresses saving AND sound.

## Characters and latest completed work

User supplied Mega and Roll ZIPs. Unmodified archives and extracted sources are in `tools/model-sources/`. The Models Resource assets are Capcom meshes/textures/skeletons, excluded from MIT; credits in `assets/characters/CREDITS.md`. Roll uses `Roll_(Cutscene)`. Both retain 18 original rigid-weight joints. Archives contain NO original animation clips; our twelve clips are newly authored.

Converter: `tools/model-sources/build_characters.py`; outputs `assets/characters/volnutt.glb`, `roll.glb`. GLBs face -Z, soles at zero. Left glove triangles are omitted only in playable variants to fit attached busters. Preserve original texture pixels, UVs and weights. Import settings must keep `animation/remove_immutable_tracks=false`, `skins/use_named_skins=true`, `meshes/generate_lods=false`; animation sampling is now 60 FPS.

Latest pass **07 is finished and rebuilt**: distinct contact/push-off/recovery poses replace mirrored leg swings, boot rotations and model-specific ground height, subtle torso counter-motion, bent elbows, run cycle .48 sec, directional cycles .56 sec. Direction changes preserve gait phase; footsteps follow animation contacts. The buster arm compensates for torso rotation. Physics speed/input responsiveness stayed unchanged. Previous version is recoverable in `backups/v6/`; older backups v1–v5 exist. Do not restore them without reason.

## Key files

- `scripts/character.gd`: imported rigs, manual AnimationPlayer advance, clip blending, stride phase, aim/recoil, forearm buster/muzzle.
- `scripts/player.gd`: movement, camera, lock-on, shooting, stats, footsteps, character selection.
- `scripts/game.gd`: dungeon, encounters, progression, saves, modes and built-in validation.
- `scripts/hud.gd`, `sound.gd`, `enemy.gd`, `navigation.gd`, `bolt.gd`, `art.gd`: corresponding systems.
- `tests/character_checks.gd`: rig/weights, clips, actual skinned boot contact, stride continuity, aim release/stability, projectile hits and character retention.
- `tests/record_video_preview.gd`: 43-second actual game/mixer recording with scripted inputs and isolated save paths.
- `README.md`, `CHANGELOG.md`: longer documentation; read only relevant sections.

## Verified current state

After latest changes: character suite **3868 checks, 0 failures**; combat suite **3207 checks, 0 failures**. Keyboard doorway/corridor traversal passes in source AND packed game. Updated pack exports and launches on local GPU successfully. Earlier UI/audio suites passed before this animation-only pass.

Example commands (set runtime environment above first):

```powershell
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tests/character_checks.gd
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tests/combat_checks.gd
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --movement-test
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --export-pack 'Windows Desktop' build\RelicDiver.pck
```

Reimport after regenerating GLBs: `--headless --editor --path . --import`. Run relevant checks after meaningful changes, not every suite repeatedly. Copy updated docs/credits into build when appropriate.

## Videos and inline delivery

Latest full video with sound: `build/preview/RelicDiver-motion-preview.mp4` (43 sec). Short movement video: `build/preview/motion-inline.mp4` (19 sec, 640×400, H.264/AAC). Previous motion retained as `previous-motion.mp4`. Raw AVI files are large; do not read them as text or include them in exports.

User wants videos playable directly in conversation. This worked via the visualize skill using a video with embedded data URI under 1 MB. Latest fragment:
`C:\Users\Temp\.codex\visualizations\2026\10\13\01a13546-24d6-7143-915a-5636c4ceb573\legends-motion-preview.html`

Read the FULL visualize skill before creating/updating inline previews. Helpers: `build/preview/embed_motion.py` and `motion-video-template.html`. Current H.264/AAC fragment plays with sound in the sandboxed preview. The newer 640×400 VP9 encoding failed browser playback despite valid file decoding; use the working MP4. First older 480×300 VP9 video did work. A localhost preview server was running on port 8769; verify only if needed. Do not publish videos externally.

## Taking over efficiently

The last requested animation refinement is complete. The following documentation/repository pass adds DESIGN.md, subsystem handoffs, Git tracking, a portable ZIP and fresh-clone setup. User is switching instances to save context/tokens. Start from this handoff and inspect only files needed for the next request; do not scan backups, dump entire scripts, rerun all tests, rebuild, or redo completed work just to establish context. Briefly acknowledge readiness, then follow the user's next task. Human playtesting is still needed; this remains a prototype, with no controller support or mid-run resume. Check Git status/log for the exact repository synchronization state.
