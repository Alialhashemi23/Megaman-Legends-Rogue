# Relic Diver handoff — 2026-10-13 (pass 10: runs that survive mishaps)

## User intent and constraints

Continue this existing local Godot project. It is a non-profit Mega Man Legends fan roguelike: colorful ancient machinery, mysterious robots, dungeon exploration, third-person free aim with optional lock-on, buster combat, and Risk of Rain-style stackable themed drops. Unlock items/weapons between runs; run power resets.

Keep the presentation and animation close to the original PS1 Legends: painted textures, original character proportions, compact springy motion, responsive controls, restrained sway. Mega is helmet-off with brown hair and blue armor. Roll is also playable. The user disliked the former blocky procedural character and stiff marching animation.

**Updated authorization:** The user subsequently requested committing this complete project and its design/handoffs to https://github.com/Alialhashemi23/Megaman-Legends-Rogue. This supersedes the earlier no-repository preference for that destination. Do not deploy, publish releases, upload personal saves or publish elsewhere without a request. Local HTTP preview is bound to 127.0.0.1 only. **Later request (pass 09):** the user asked for seamless online co-op playable in the browser on their own newly registered domain, hosted from their own computers through a Cloudflare Tunnel. The repo now ships the web build, lobby server and deployment files; the user performs the deployment (never commit `.env` or tunnel tokens). No subagents unless the user asks. Proceed autonomously on authorized changes; avoid repeated confirmations.

Design intent is in DESIGN.md. Subsystem handoffs and a fresh-instance prompt are indexed in docs/handoff/README.md. Repository packaging and exclusions are explained in docs/handoff/REPOSITORY.md.

## Location and launch

Workspace: `C:\Users\Temp\Documents\Codex\2026-10-13\hey-i-want-to-build-a`

- `Play.cmd` launches source; `Edit.cmd` opens the bundled editor.
- Portable game: `build/RelicDiver.exe` with adjacent `RelicDiver.pck`.
- Fresh clone: Play.cmd/Edit.cmd set up the engine from the tracked `build/RelicDiver-Windows.zip`. Loose engine executables, caches, captures and personal saves are ignored; editable models, original ZIPs, audio sources and notices are tracked.
- Engine: `tools/Godot_v4.7.1-stable_win64_console.exe` (GUI executable also bundled).
- PowerShell. Set APPDATA and LOCALAPPDATA to workspace `tools/runtime` for tool/test runs.
- Python: `C:\Users\Temp\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`; NumPy installed. FFmpeg/ffprobe in PATH.

## Latest completed work: mishap-proof runs (pass 10)

The user said multiplayer robustness was the biggest gap and wanted runs to persist correctly before moving on.

- **Host migration:** a leaving or crashing host never ends the dig; the lowest remaining slot takes over.
- **Exact rejoin:** stable player identity plus a mirrored build roster means a refresh, crash or rejoin returns the exact build.
- **Reconnect:** dropped sockets auto-reconnect for 90 s, with the dig frozen meanwhile.
- **Checkpoints:** every machine saves every 5 s and on build changes, atomically, and the host also stores one on the server. Empty lobbies wait 15 min; a forgotten lobby is recreated under its code from a local save. Solo digs get Continue Dig.
- **Guards and hardening:** confirm-before-leave and two-click destructive buttons, protocol versioning, message shape validation.
- **Co-op features:** spectating, chat, pings, quick callouts, kick, lock and lobby passwords.

Details: `docs/handoff/NETWORK.md`. User guide: `docs/ONLINE.md`, section "Your run is safe".

## Online co-op (pass 09)

Browser play plus online co-op for up to four diggers. Pass 09 was built in a Linux cloud container with Godot 4.7.1 (Linux editor and export templates), Node 22, Xvfb and Playwright Chromium.

- **Flow:** Title → Play Online (name, public/private lobby, lobby browser, join by code) → lobby room (party, character/buster, Copy Invite Link) → host starts. Invite links `https://domain/?lobby=CODE` (or `/j/CODE`) open straight into the lobby. Late joiners sync into a dig in progress.
- **Rules (user-chosen):** shared run with personal builds. Shared scrap and XP; every digger picks from each cache; one guardian core each; party-scaled robots; downed/revive by standing close; the run ends when everyone is down; the lift waits for the team. Online menus don't pause.
- **Architecture:** host-authoritative over a WebSocket relay (`server/`, Node + `ws`). Deterministic per-floor seeding; victim decides digger damage; shooter decides robot damage. Details and protocol: `docs/handoff/NETWORK.md`. Deployment: `docs/ONLINE.md` (Docker Compose + cloudflared, or Host-Online.cmd).
- **Web specifics:** threaded export needs COOP/COEP headers (the server sends them) and a secure context (HTTPS domain or localhost). Web saves live in `user://` (IndexedDB). Click-to-aim after a networked start, because browsers require a gesture for pointer lock.
- **Bundles:** `build/RelicDiver-Web.zip` (tracked, served by the Docker image) and a refreshed Windows `.pck`/ZIP. The Windows build can join via Play Online → Dig Server (`wss://domain/ws`).

Not yet done: a human playtest of co-op balance (party scaling numbers are first guesses) and a real deployment on the user's domain (the user needs to create the tunnel and token). Host migration and run persistence followed in pass 10.

## Implemented

Complete playable three-descent loop, seeded branching rooms, five cover arrangements, robot navigation and telegraphed attacks, three guardians with different attack mixes, three busters, thirteen stackable parts, XP, scrap, caches, healing, unlocks and local records. Console-inspired cobalt/cream/yellow menus, Life gauges, custom icons and bundled fonts. Seven original music cues rendered locally using GeneralUser GS/FluidSynth, 29 effects, ambience, buses, crossfades and sound settings.

Source saves: `save/archive.json`, `save/audio.json`. Portable saves: `build/save/`. Preserve them. Preview/test scripts use isolated paths; `game.smoke_test` suppresses saving AND sound.

## Characters and motion pass 07

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

Pass 10 (Linux): server 9/9; run persistence 24/0 (exact restore, damaged files, 400 fuzzed messages with no script errors); `tests/net_test.sh` passes all 7 processes (co-op play, guest refresh, Wi-Fi drop and auto-reconnect, host crash and migration, host return, empty-lobby resume from the server checkpoint, server-restart resume from a local checkpoint); `tests/web_e2e.mjs` passes in real Chromium including a guest page reload (beforeunload prompt, IndexedDB save found, resynced) and a host page reload (hosting moved to the guest, host rejoined). Character 3868/0, combat 3207/0, UI 47/0, audio 66/0; smoke, combat, movement and persistence modes pass. Renders in `screenshots/coop-*.png`.


Pass 09 (Linux): server tests 5/5. `tests/net_test.sh` passes (host + guest + late joiner, identical floors at B1/B2, hits, drops, choices, revive, lift, late join, shared ending). `tests/web_e2e.mjs` passes in real Chromium (menus, lobby creation, clipboard invite link, join via link, both diggers in one dig). Character 3868/0, combat 3207/0, UI 47/0, audio 66/0; smoke, combat, movement and persistence modes pass. Co-op HUD renders: `screenshots/coop-*.png`.


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

The last requested work, mishap-proof runs and co-op communication (pass 10), is complete on branch `online-coop`, on top of pass 09's online co-op. The user's next step is deployment per docs/ONLINE.md; offer help with the tunnel setup and co-op tuning after they play. Earlier: the animation refinement, then DESIGN.md, subsystem handoffs, Git tracking, a portable ZIP and fresh-clone setup. User is switching instances to save context/tokens. Start from this handoff and inspect only files needed for the next request; do not scan backups, dump entire scripts, rerun all tests, rebuild, or redo completed work just to establish context. Briefly acknowledge readiness, then follow the user's next task. Human playtesting is still needed; this remains a prototype, with no controller support or mid-run resume. Check Git status/log for the exact repository synchronization state.
