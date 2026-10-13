# Local build history

## 11 — Controller support, Options and Leave Dig

- Full controller support (Xbox-style names; works with any pad Godot recognises):
  - **Play:** left stick moves, right stick looks, RT fires, LT locks on, A jumps, B dashes, X salvages/uses, LB pings, View opens Buster Parts, Start opens the menu, and the D-pad sends callouts.
  - **Menus:** D-pad or left stick moves, A confirms, B goes back, Y switches digger on the title.
  - **Prompts and feel:** button prompts follow the last device used; hits rumble the controller.
- New **Options** menu (title and pause):
  - **Sound:** master, music, effects, ambience, mute.
  - **Display:** fullscreen, camera motion, field of view.
  - **Controls:** mouse sensitivity, controller look speed, invert look, vibration.
  - **Controls & bindings:** rebind every action for keyboard/mouse and controller separately, with automatic swaps on conflicts and a reset to defaults. Settings save to `settings.json` (`audio.json` keeps the volumes).
- **Leave Dig** in the pause menu for everyone, with a second click to confirm. Online, a leaving host hands the dig to the others; the host also has **End Dig for Everyone**.
- Solo digs no longer save mid-run (they're short). Online digs keep their checkpoints so rejoining still works.
- New checks: controller, options, rebinding and leave suite (39). Existing suites pass.

## 10 — Runs that survive mishaps, plus co-op communication

- Host migration: when the host leaves or crashes, the next digger takes over hosting from the world they already see and the dig continues.
- Stable player identity and a mirrored roster of every digger's build: a refresh, crash or rejoin returns the exact build (parts, level, experience, Life, downed state, an unfinished part choice and queued level-ups).
- Automatic reconnection for dropped connections (the dig freezes with a *Reconnecting…* banner for up to 90 seconds). A newer tab replaces an older one cleanly.
- Checkpoints: every machine saves the dig every 5 seconds and on every build change (atomic writes with a backup copy), and the host also stores one on the server. Empty lobbies wait 15 minutes for returning diggers; a dig can also be recreated under its old code after a server restart. Solo digs gain **Continue Dig**.
- Mishap guards: the browser asks before leaving mid-dig; leaving, ending for everyone, removing players and replacing a saved dig need a second click; abandoned digs still count their machines.
- Hardening: protocol versioning (mismatched builds can't share a lobby), shape validation for every network message, and guarded lobby commands.
- Co-op features: spectator camera while down, text chat (lobby and dig), team pings, quick-chat callouts with speech bubbles, host kick, lobby lock and optional lobby passwords.
- New checks: run persistence suite (24), server suite (9), a seven-process network gauntlet (refresh, Wi-Fi drop, host crash, host return, empty-lobby resume, server-restart resume) and browser reload tests.

## 09 — Online co-op in the browser

- Added a web export (Godot threaded WebAssembly build) and a small Node server that hosts it with the required cross-origin isolation headers, pre-compressed downloads and a WebSocket lobby relay. Deployment targets the user's domain through a Cloudflare Tunnel (Docker Compose or Host-Online.cmd).
- Title → **Play Online**: name entry, public/private lobbies, a live lobby browser, join by code, and invite links (`/?lobby=CODE`) that open straight into the lobby. The lobby room shows the party with each digger's character and buster, plus a copy-link button.
- Co-op for up to four diggers in one seeded run. The host simulates robots and loot; each digger controls their own movement, Life and build. Shared scrap and XP, a personal cache pick for everyone, a guardian core per digger, party-scaled robots, downed/revive by standing close, the lift waits for the team, and late joiners sync into a dig in progress.
- Online menus and part choices no longer pause the dig; choosing is protected. Teammate nametags, a team Life panel, revive prompts and a click-to-aim hint for browsers.
- Saves use browser storage on the web; desktop saves are unchanged. The Windows build can join lobbies through **Dig Server**.
- New checks: server tests, a three-instance host/guest/late-join network test, a real-browser lobby test and co-op HUD renders. Existing character, combat, UI, audio, smoke, movement and persistence checks pass.

## 08 — Design documentation and repository handoff

- Added DESIGN.md and focused handoffs for implementation, art/animation, audio/UI, playtesting and repository workflow, plus a concise fresh-instance prompt.
- Updated HANDOFF.md and project instructions to record the user's new authorization for the named GitHub repository.
- Added selective Git exclusions that preserve editable project inputs and licenses while omitting caches, backups, personal saves and raw recordings.
- Packaged the tested Windows runtime, content pack and notices into a portable ZIP; added fresh-clone setup and repeatable packaging scripts.
- Preserved the repository's initial README commit as the base for the project import. Gameplay remains the tested pass 07 implementation.

## 07 — Legends-inspired motion refinement

- Replaced mirrored leg swings with separate contact, push-off and recovery poses, restrained torso counter-motion, bent elbows and rolling boots for both characters.
- Baked model-specific boot contact into body height, retaining original geometry, skin weights and texture pixels.
- Matched running cadence to traversal speed and synchronized footstep effects to gait contacts.
- Preserved stride phase when changing between running, backpedaling and strafing, with short transitions and full torso compensation for the buster arm.
- Added full-cycle boot contact, aim stability, stride continuity and footstep checks. Character and combat suites and keyboard traversal pass.
- Recorded a new gameplay preview with sound and preserved the prior build in `backups/v6/`. Updated the local portable pack.

## 06 — Original Legends characters

- Imported the supplied Mega Man Volnutt and Roll Caskett archives, credited to The Models Resource submitter Xinus23 and Capcom. Retained unmodified archives and source hashes locally.
- Replaced the procedural player with textured, skinned GLB models. Preserved both original 18-joint rigs and authored twelve new movement, combat and outcome clips.
- Added title-screen Mega/Roll selection with mouse, keyboard and C shortcut, sharing the same roguelike progression and buster options.
- Layered aiming and recoil over locomotion; attached original local busters and muzzle markers to the forearm. Replaced intersecting glove geometry in playable variants.
- Rendered actual model portraits for the HUD and pause menu, including correct character names.
- Added rig, weight, animation, aiming, firing and descent-retention checks plus a six-pose render gallery.
- Preserved the audio-pass build in `backups/v5/` and updated the local portable build.

## 05 — Original music and sound

- Composed seven original cues with editable MIDI sources: title, three descents, guardian, clear and defeat. Rendered locally with GeneralUser GS 2.0.3 and FluidSynth.
- Replaced runtime tone placeholders with 29 layered effects and a stereo ruin ambience loop; added weapon variants, footsteps, jumps, landing, lock-on, robot destruction and distinct pickup feedback.
- Added music crossfades, guardian transitions, menu ducking, 3D robot effects, independent audio randomness, voice caps, reverb and a master limiter.
- Added a console-style sound menu with separate Master, Music, Effects and Ambience levels, saved separately from run records.
- Kept composition tools, renderer and SoundFont local and outside the playable content pack. Included source credits and license text.
- Added audio routing/cue/menu checks, a runtime mix capture and a soundtrack preview. Preserved the prior build in `backups/v4/`.

## 04 — Console-style UI

- Replaced the dark card layout with framed cobalt windows, a mechanical blue background, outlined lettering, segmented Life meters, and a yellow selection cursor.
- Bundled Russo One and Barlow Semi Condensed fonts with their open-font licenses.
- Drew a 32-icon equipment atlas, a Volnutt portrait, and a menu background pattern locally.
- Redesigned title, HUD, pause, Buster Parts, collection, upgrade choices, and dig results.
- Added keyboard navigation and scrollable part inspection; kept mouse and number-key shortcuts.
- Added uniform UI scaling and a widescreen safe area, and checked three window sizes.
- Added UI interaction checks and a staged render gallery that leaves player saves untouched.
- Preserved the previous version in `backups/v3/`.

## 03 — Combat and exploration

- Added committed attack windups and visible ground warnings for swings, sentry shots, charges, shockwaves, bombardment, and crossing beams.
- Gave the three guardians different attack mixes, palette variations, and an overdrive recovery transition.
- Added muzzle flashes, bolt trails, hit and kill markers, enemy flashes, knockback, recoil, impact rings, and optional camera feedback.
- Made Siege Buster wall impacts splash nearby exposed enemies while respecting solid cover.
- Added five cover arrangements and dungeon grid navigation; robots can route around obstacles and through connected doors.
- Added behavior checks for attack timing, evasions, cover, pathfinding, generation, and pause handling.
- Preserved the previous version in `backups/v2/`.

## 02 — Clean PS1 visual pass

- Added a locally authored helmet-off Volnutt fan model with blue armor, brown hair, a painted face, and a left-arm buster.
- Added five editable painted texture sources, enclosed chambers, warm lamps, ceiling beams, and new robot silhouettes.
- Preserved the original prototype in `backups/v1/`.

## 01 — First playable

- Created the original three-descent run loop, stackable relics, busters, experience, unlocks, procedural rooms, guardians, UI, sound, and local saves.

Passes 01–07 were developed locally without a repository or publishing step. In pass 08 the user explicitly authorized committing the project to Alialhashemi23/Megaman-Legends-Rogue. No hosted game deployment or release publication was requested.
