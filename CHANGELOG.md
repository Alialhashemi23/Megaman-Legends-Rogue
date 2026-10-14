# Local build history

## 21 — Android accounts and startup updates (local, not deployed)

- Android device-code sign-in, origin-isolated Keystore-encrypted sessions, startup recovery, suspension-safe outbox/checkpoints and wall-clock device-code expiry. No persistent plaintext tokens.
- Startup update metadata with integer version codes, optional/required online update choices and explicit system-browser downloads; immutable local APK staging with checksums/signing fingerprints and opt-in server routes. Nothing published live.
- Controller-accessible Credits / Licenses with full engine, asset, audio and font notices. Android test APK code 3, version 0.18.0; game protocol remains 7.
- Client Android 44, account 34 and UI 47 checks; server update/relay 10 tests; native emulator Keystore encryption/tamper/sign-out/process restart/in-place upgrade passed. Retroid cross-play and installer failure cases remain unverified.

## 20 — Game account sync (deployed with authorization)

- Browser cookie sign-in and Windows device-code sign-in, with cobalt account menus and controller navigation. Windows credentials stay in memory; no plaintext token files.
- Separate Guest/account profiles and durable account outboxes. Results retry without duplicate rewards, pending Zenny cannot be spent, purchases use server revisions, and guest adoption requires preview/confirmation into an empty account.
- Online account run starts, explicit takeover, lease heartbeats, account-owned checkpoints, and fresh lobby tickets on every connection. Guest identity stays separate. Game protocol remains 7.
- Checks: 34 account client checks; progression 138, resume 24, co-op feedback 40, UI 47, Options 39; smoke and reconnect/host-migration/server-restart suites; server 34/34 with PostgreSQL; real Godot HTTP tests with deliberately lost committed responses and signed-in relay identity. Real browser sign-in preserves a pending invite under COOP/COEP; an in-game purchase survives reload and syncs to another browser and Windows.

## 19 — Account server (no game change)

- The server can run player accounts: email sign-up with verification and password reset, Windows/Android sign-in with a code approved in the browser, and a progress API that records run rewards and Workshop purchases exactly once. Off unless configured (`docker-compose.accounts.yml`, docs/ACCOUNTS-OPS.md), with encrypted daily database backups.
- The game doesn't use accounts yet; that's the next update. Guest play, co-op and game protocol 7 are unchanged.

## 18 — Android test build (no gameplay change)

- Native ARM64 Android APK (`tools/package-android.ps1`, app id `dev.galosengen.relicdiver`), landscape, same game and online lobbies as the browser and Windows builds. Verified on the Android emulator only; not yet on the Retroid Pocket 5.
- Saves, settings, audio settings, online identity and checkpoints use per-app storage on Android through `DiverPaths`. Desktop and web storage are unchanged. No gameplay or protocol change: still game protocol 7.

## 17 — Shared co-op map, waiting part picks and cache icons

- **Shared map:** rooms any teammate explores appear on everyone's ruins map; clears were already shared. Room banners still greet you the first time you walk in.
- **Waiting part picks:** when a teammate opens a cache, you get a "Part Choice Waiting" notice instead of the choice screen taking over. **Tab / Select** opens it (and opens Buster parts when nothing is waiting). The pick screen shows your fitted parts. Online, **Tab / Select** or **Esc / B** puts a pick aside for later; the same three parts stay on offer. Waiting picks survive refreshes, rejoins and host migration.
- **Cache icons on the map** for revealed rooms: grey while sealed, gold when ready, flashing cyan while your pick from it waits, dark once opened.
- Game protocol 7: update all co-op clients together. Checkpoint format 3 is unchanged; saved digs from build 16 still restore.

## 16 — Signature attacks, Zenny, Workshop and portable progress

- Four signature attacks: Pulse Mega, rapid/support Roll, heavy/splash Tron, ballistic-bomb Servbot. Servbot gains its own small collision capsule, lower camera, faster movement and 65 base Life.
- Zenny rewards and five purchased skill nodes per digger, including unique signature circuits and part-pool research. New part gates: 40/100/220; existing earned unlocks migrate.
- Versioned, atomic progress saves plus validated, checksummed save-code export/import with a replacement preview. Purchases persist immediately and survive browser reloads.
- Whole-floor or zoomed/scrolling map option. Actual model-rendered Volnutt portrait replaces the loader illustration and Godot favicon, with explicit exported browser icons.
- Fixed browser text-field focus during redraw; online starts/rejoins wait for a real click before pointer lock.
- Game protocol 6 / checkpoint format 3: update all co-op clients together; older active dig checkpoints are incompatible. No live deployment in this branch.


## 15 — Tron Bonne and Servbot

- Two more playable diggers from the user's supplied Mega Man Legends models: **Tron Bonne** and a **Servbot**. Pick them on the title screen (C or Y cycles through all four) or in an online lobby.
- Both use the same twelve authored animations, attached buster, parts and progression as Mega and Roll for now. The Servbot is about half their height and waddles when it runs.
- Old and new builds can't share a lobby; refresh the page to update.

## 14 — Harder machines, a loading screen and an icon

- **Difficulty** (the user had cleared ten digs without being hit):
  - Robots have about 60% more Life and gain 65% per descent instead of 40%. Each chamber holds one more.
  - Every attack hits harder and now scales with depth, including sentry and guardian bolts.
  - Warnings stay, but wind-ups and recoveries are 25% shorter on B1 and 40% shorter on B3. Robots move faster and hostile bolts fly about 60% faster.
  - Sentries and guardians lock their aim just before firing and lead a moving digger; the warning line turns red when it locks.
  - Guardians have about three times the Life, attack faster in overdrive, and shield themselves briefly as overdrive begins so they can't be burst down through it.
- **Loading screen:** the browser build opens on a Relic Diver page with a lock-on spinner around Mega, a Life-gauge progress bar with a percentage, and rotating flavour text. The Godot logo no longer appears at startup.
- **Icon:** the browser tab and the Windows build use a Mega portrait.
- The Broken Foundry's pipes now run overhead instead of across doorways.

## 13 — Bigger, more varied ruins and a proper map

- **Rooms are 50% bigger** (30 m across instead of 20 m, with higher ceilings), and corridors are longer.
- **Hallways fork.** Floors now include passage junctions: some fork three or four ways, some loop back to rooms you've seen, and some dead-end at hidden salvage vessels. Rooms connect only where there is a real corridor.
- **New rooms in the pot,** one of each on every floor alongside the five cover arrangements:
  - **Grand Concourse:** a hall twice the size of a normal room, with a colonnade, a raised dais reached by ramps, and a larger group of machines.
  - **Stepped Vault:** a jump puzzle. Stepping blocks climb to a high ledge with a free hidden cache and salvage.
  - **Terrace Hall:** a raised terrace along one wall with a ramp at each end. Robots take the ramps to follow you up.
- **Ruins map:** now a to-scale plan of the floor. The arrow sits at your exact position and turns with your camera, corridors are drawn where they really run, and teammates show as coloured dots online.
- Attack warnings and blasts follow the floor a robot or its target stands on, so they work on raised ground.
- Old and new builds can't share a lobby (the ruins differ); refresh the page to update.

## 12 — Smoother browser play

- The first shot that lands no longer freezes the browser game for a moment: the hit flash, sparks and damage number are prepared while the floor loads.
- Each room's floor tiles draw as one mesh, so long views down the halls cost roughly 40% fewer draw calls. The ruins look the same.

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
