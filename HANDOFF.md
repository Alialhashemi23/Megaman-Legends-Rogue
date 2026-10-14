# Relic Diver handoff — 2026-10-14 (account and Android planning; pass 16 implemented)

## Latest request: accounts and Android — planning only

On `codex/next-features-volnutt`, [docs/handoff/ACCOUNTS-ANDROID-PLAN.md](docs/handoff/ACCOUNTS-ANDROID-PLAN.md) plans account logins and durable permanent progress across browser/Windows/Android, a native Retroid Pocket 5 APK, shared co-op lobbies and startup update checks. Hosting/cost and login choices are open; the user asked whether managed hosting costs money, and the plan covers a free pilot versus paid service and self-hosting tradeoffs. No services provisioned, gameplay changed or builds regenerated. This is not an implementation or deployment pass.

The feature branch had the same gameplay as `main`, which also contained two newer planning commits. Their pending map sharing, deferred cache selection and chest-icon requests are preserved in NEXT-FEATURES.md. That file and docs/handoff/README.md link the new plan. Account saves and Android remain unimplemented; existing local saves/save codes and shipped bundles are unchanged.

## Current feature branch

Implemented the agreed NEXT-FEATURES brief on `codex/next-features-volnutt`, based on main `9c4d309`. The user requested commits and a pushed feature branch for later merging. Do not deploy the live site during this work. Full overview and validation: `docs/FEATURE-REPORT.md`.

- One signature attack per digger: Mega Pulse, Roll Needle plus 2× revive rate, Tron Siege splash, Servbot ballistic bombs, 65 Life, +18% speed, 1.05 m capsule and 0.85 m camera pivot.
- `scripts/progression.gd`: Zenny, 5 nodes × 4 diggers, table-driven costs, prerequisite checks, profile v2 migration, checksummed save codes. Existing earned part unlocks survive raised 40/100/220 gates. Moderate permanent stat bonuses are now part of DESIGN pillar 5.
- Workshop from title/results, save-code preview/confirmation and atomic profile writes, plus a revisioned synchronous browser recovery mirror. Imports blocked during runs, online lobbies and pending saved digs. All combat-relevant purchased skills, Pulse shot count and Roll repair timer are part of builds/checkpoints.
- Options offers fitted or scrolling/zoomed maps. Loader/project icon/favicon reuse the supplied model-rendered Volnutt portrait; both package scripts ship the web image files.
- NET_VERSION 6, CHECKPOINT_VERSION 3. Older active checkpoints are incompatible; persistent profiles migrate. Everyone in co-op must update together.
- Tests: new `tests/progression_checks.gd`, `tests/web_progression.mjs`; screenshot generator `tests/next_features_preview.gd`. Test profiles isolated under save/. No user profiles or secrets committed.
- Difficulty timing remains the pass-12 tuning pending human feedback; no feedback was provided to justify another blind change.

Earlier pass notes below are historical and may describe superseded behavior.

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

## Deployment

The user hosts locally (a home PC) for now, at **https://megaman.galosengen.dev** (`galosengen.dev` is on Cloudflare) through a Cloudflare Tunnel. The tunnel route points `megaman.galosengen.dev` at `http://relic-diver:8080` (Docker) or `http://localhost:8080` (Host-Online.cmd). The desktop build's default server is `wss://megaman.galosengen.dev/ws`. Host-Online.cmd restarts the server if it stops. A VPS may come later; the setup is identical there.

## Latest completed work: live deployment, bigger varied ruins, to-scale map (pass 12, 2026-10-13)

Done on the user's Windows PC (`D:\code repos\Megaman-Legends-Rogue`, branch `online-coop`).

- **Deployed:** https://megaman.galosengen.dev is live from this PC via `docker compose` (containers `relic-diver` and `cloudflared`; the tunnel token is in the untracked `.env`). After changing gameplay: `tools\package-web.ps1`, then `docker compose up -d --build relic-diver`. The Web export templates for 4.7.1 are installed in `%APPDATA%\Godot\export_templates\4.7.1.stable`.
- **User-reported fixes:** a first-hit freeze in the browser (hit flash and damage-number shaders are now warmed in `warm_hit_effects`) and slow long views (each room's floor tiles are one MultiMesh, `DiverArt.tiles`).
- **User requests:** minimap that tracks exact position with a camera-facing arrow and consistent corridors; forked hallways; more room types (big room, jump puzzle, elevation); rooms at least 50% bigger.
- **Implementation:** `scripts/ruins.gd` plans and builds floors. Rooms carry `kind`, `half`, `cells`, `height`, `layout` (0-4 cover, 5 Stepped Vault, 6 Terrace Hall, 7 Grand Concourse, 8 passage). `game.links` are the corridors; `game.platforms` gives `floor_height()`; `game.nav_open` re-opens platform tops and ramps for robots. Robots chase directly only when on the same level as their target, otherwise they path (up ramps). `NET_VERSION` 3, `CHECKPOINT_VERSION` 2.
- **Difficulty (user: "too easy, never hit in ten clears; keep the telegraphs but faster; bosses die instantly"):** all numbers live in `scripts/enemy.gd`: `hit(base, per_floor)` for damage, `pace()` for wind-up and recovery length, `lock_aim()` for sentry and guardian shots that lead the target just before firing, `shield` for the guardian's overdrive guard. Life is set in `_ready`; hostile bolt speed in `bolt.gd`. These are first-pass values awaiting the user's playtest. `NET_VERSION` is now 4.
- **Loading screen and icon:** `web/shell.html` is the Web export's custom shell (fonts copied by `tools/package-web.*`); `assets/ui/icon.png` is the project icon; the boot splash image is off.
- **Tron Bonne and Servbot:** the user supplied both model archives (`tools/model-sources/tron.zip`, `servbot.zip`). `build_characters.py` takes a per-rig joint-name map; `DiverCharacter` has `COUNT`, `IDS` and per-character buster colours and scale, and handles the Servbot's single-joint arm. All four share mechanics. The user's planned next steps, not started and with design decisions still open: per-character attacks, a currency and per-character skill trees bought after a run, and deciding how that progress is saved. The Servbot still uses the full-size collision capsule and camera height. `NET_VERSION` is now 5.
- **Verified:** character 6605/0 with four diggers; combat 7765/0 after the difficulty pass (earlier 7723/0), character 3868/0, UI 47/0, audio 66/0, options 39/0, run persistence 24/0; smoke, combat, movement and persistence modes; `tests/net_test.sh` passes on Windows through Git Bash. Scratch probes (not kept) generated 120 floors with no unreachable rooms or bad spawns, climbed the jump puzzle with real input, and confirmed a robot follows a digger up a ramp. Not yet checked: a human playtest of the new rooms' balance and feel, and `tests/web_e2e.mjs`.

## Historical brief: implemented in pass 16

**The full brief, with code locations, open questions and defaults, is in `docs/handoff/NEXT-FEATURES.md`. Read that before starting.** Summary:

The user agreed to all of the following on 2026-10-13 ("the asks I all agree to"). Build them one at a time, in this order.

1. **Individual attacks per character.** Mega keeps the Pulse Buster as the all-rounder. Roll gets the Needle Buster's rapid fire plus a support ability (faster revives or a repair drone). Tron gets the heavy Siege shots or commands a few Servbots that fight beside her. The Servbot is small and fast with low Life and throws bombs in an arc; give it a smaller collision capsule and a lower camera at the same time. Still to settle with the user: one fixed weapon per character, or a small set to unlock.
2. **Skill trees and currency.** Zenny, earned per run from depth reached, guardians beaten and leftover scrap, spent in a shop after the results screen on a tree per character. Raise the gates on existing unlocks and add more. Still to settle: permanent power (then rescale difficulty) or sidegrades only. DESIGN.md pillar 5 currently says no permanent starting power, so update it with whatever the user chooses.
3. **Saving.** Keep browser storage (`user://`, already survives a refresh) and add an export/import save code. Server-side saves only if the user later wants progress to follow players between devices.

Smaller agreed items: a zoomed, scrolling minimap option, and tuning the pass-12 difficulty numbers after the user's playtest.

## Controller, Options, Leave Dig (pass 11)

The user asked for a way to leave a run, controller support and a basic options menu, and said solo mid-run saving isn't needed (runs are short).

- `scripts/settings.gd` owns the InputMap: every gameplay action has one rebindable keyboard/mouse and one controller binding, plus fixed sticks and menu navigation. Defaults are Xbox-style (RT fire, LT lock, A jump, B dash, X use, LB ping, View parts, Start menu, D-pad callouts). Prompts follow the last device; hits rumble. Saved to `settings.json`.
- Player, game and HUD read actions only. Key and button presses are handled per event; trigger and stick edges are tracked from motion events (holding never repeats a toggle), with menu repeat while the stick is held.
- Options (title and pause) cover sound, display (fullscreen, camera motion, FOV) and controls (mouse sensitivity, look speed, invert, vibration). Controls & bindings has two columns, swap-on-conflict and reset.
- The pause menu has **Leave Dig** for everyone. Online, the leaver's slot frees and hosting migrates; the host also has End Dig for Everyone. `solo_checkpoints = false`, so only online digs checkpoint.

## Mishap-proof runs (pass 10)

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

Pass 11 (Linux): options/controller suite 39/0 (simulated controller: stick movement/look, triggers fire and lock without repeat toggles, Start/B/View, D-pad and stick menu navigation, Y digger switch, options adjustments, rebinding with swaps and persistence, reset, Leave Dig confirm, solo digs unsaved). UI 47/0, audio 66/0, character 3868/0, combat 3207/0, run persistence 24/0, network gauntlet passes, server 9/9; smoke, combat, movement and persistence modes pass. Renders: `screenshots/options-*.png`.


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

The last requested work, controller support, Options and Leave Dig (pass 11), is complete on branch `online-coop`, on top of pass 10's mishap-proof online runs and pass 09's online co-op. The user's next step is deployment per docs/ONLINE.md; offer help with the tunnel setup and co-op tuning after they play. Earlier: the animation refinement, then DESIGN.md, subsystem handoffs, Git tracking, a portable ZIP and fresh-clone setup. User is switching instances to save context/tokens. Start from this handoff and inspect only files needed for the next request; do not scan backups, dump entire scripts, rerun all tests, rebuild, or redo completed work just to establish context. Briefly acknowledge readiness, then follow the user's next task. Human playtesting is still needed; this remains a prototype (no authored story; solo digs intentionally don't save mid-run). Check Git status/log for the exact repository synchronization state.
