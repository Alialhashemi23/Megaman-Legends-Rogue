# Relic Diver — The Tidal Archive

A third-person 3D dungeon roguelike fan prototype made in Godot 4.7.1, inspired by Mega Man Legends and the stacking item combinations of action roguelikes. Play as helmet-off Mega Man Volnutt, Roll Caskett, Tron Bonne or a Servbot, using the original PS1 models and textures supplied from The Models Resource. Explore seeded ruins alone or with up to three friends online. Environment art, animation, music, sound effects and ambience were authored for this project.

This is a non-profit fan project, not affiliated with Capcom. See [Credits and licensing](#credits-and-licensing).

## Play

- **Browser:** https://megaman.galosengen.dev (desktop Chrome, Edge, Firefox or Safari).
- **Windows, from this folder:** double-click **Play.cmd**. On a fresh clone it extracts the tracked `build/RelicDiver-Windows.zip` and prepares the pinned Godot runtime first. No installation, account, network connection or extra downloads are needed for solo play.
- **Portable:** extract `build/RelicDiver-Windows.zip` and run **RelicDiver.exe**, keeping `RelicDiver.pck` and the notices beside it. The executable is the full Godot runtime, so it is larger than a normal release export.
- **Android development build:** `tools/package-android.ps1` builds a test-signed ARM64 APK with account sign-in and secure sessions. Emulator-checked; Retroid testing and public downloads are pending. See [Android updates](docs/ANDROID-UPDATES.md). Credits / Licenses is available from the title.
- **Edit:** **Edit.cmd** opens the project in the bundled editor. The entry point is `project.godot`; gameplay lives in `scripts/`.

## Diggers

| Digger | Signature attack | Notes |
|---|---|---|
| Mega | Pulse Buster, the all-rounder | |
| Roll | Rapid Needle Buster | Revives teammates twice as fast |
| Tron | Heavy Siege Buster with cover-aware splash | |
| Servbot | Arcing salvage bombs | 65 base Life, 18% faster, smaller hitbox and lower camera |

Press **C** (controller **Y**) on the title screen to cycle diggers. Each has their own Workshop tree (see [Progression](#progression)).

## Controls

Gameplay actions can be rebound in **Options → Controls & bindings** (sticks, menu navigation, upgrade picks, digger switch and mute are fixed). Prompts follow the last device you used.

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move | WASD | Left stick |
| Aim / camera | Mouse | Right stick |
| Fire | Hold left mouse | RT |
| Lock on to a visible enemy | Q or right mouse | LT |
| Jump | Space | A |
| Dash (brief invulnerability) | Left Shift | B |
| Open a cache, salvage, use a well or lift | E | X |
| Buster parts and stats (pauses solo); opens a waiting part pick first | Tab | Select / View |
| Pause / menu | Escape | Start |
| Pick an upgrade on a choice screen | 1, 2, 3 | D-pad / stick + A |
| Ping (online) | G or middle mouse | LB |
| Chat (online) | T or Enter | — |
| Quick callouts (online) | 1–4 | D-pad |
| Switch digger (title) | C | Y |
| Mute | M | — |

Menus: arrows or the mouse to browse, Enter to confirm, Escape to go back (controller: D-pad or left stick, A, B). The mouse wheel scrolls part lists.

## Your first descent

1. Pick a digger and begin. Open the golden starter cache on your left with E for a free part.
2. Follow doorways into connected chambers. The ruins map reveals rooms as you explore and outlines the guardian chamber in gold once you're nearby.
3. Shoot the machines, dash through attacks and collect their scrap and experience. Nearby drops move toward you.
4. Clear a room to unlock its cache and earn five bonus scrap. Spend scrap on a choice of three parts, or save it for a restoration well. Vessels hold free salvage.
5. Levelling up offers a choice of damage, Life or fire-rate upgrades.
6. Defeat the guardian to power the lift. You can keep exploring first. Lifts keep your build and restore 25% Life.
   The first and second guardians also give each digger a **guardian milestone**: a choice of three major upgrades for the rest of the dig, weighted toward parts you have fitted (each also works without them). They are Arc Conductor, Wildfire Core, Glacier Drive, Twin Capacitor, Fortune Prism, Bulwark Frame, Scavenger's Instinct, Opening Salvo, Second Wind and Kinetic Loader. The final guardian ends the dig, so it gives its part reward only. Regular parts and level-ups still stack as before.
7. Survive three descents and activate the extraction beacon to win.

There is no countdown or time-based difficulty. Explore at your own pace; difficulty rises with each descent.

**Combat tips.** Every robot attack is telegraphed: melee swing arcs, sentry aim lines that lock just before firing, charge lanes, bombardment circles, shockwaves and beam lanes. Leave marked zones before the wind-up ends, jump over shockwaves or dash through with invulnerability. Solid cover blocks melee, shockwaves, beams and splash. Lock-on releases when a target stays behind cover for 0.75 s. At half Life, guardians shield briefly and enter overdrive.

## Content

- Three ruin palettes across three descents: Tidal Archive, Garden of Engines, Heart of the Machine.
- Seeded floors of 8, 9 and 10 rooms, joined by corridors that fork, loop back or dead-end at hidden salvage.
- Five chamber arrangements (Pillar Gallery, Relay Chamber, Salvage Archive, Coolant Works, Broken Foundry) plus a two-cell Grand Concourse with a raised dais, a Stepped Vault jump puzzle with a ledge cache, and a Terrace Hall whose ramps robots can follow you up.
- Chase robots, floating sentries, charging armored machines and three guardians:

| Descent | Guardian | Attacks |
|---|---|---|
| 1 | Archive Keeper | Fan bursts and a nearby ground shockwave |
| 2 | Verdant Engine | Three marked bombardment circles, fan bursts and a shockwave |
| 3 | Core Warden | Crossing beam lanes, wider fan bursts and a shockwave |

- Thirteen stackable parts, experience levels, scrap, healing wells, paid caches, enemy drops and salvage vessels.

## Parts and combinations

| Part | Effect per stack |
|---|---|
| Sunken Lens | +16% damage |
| Clockwork Spring | +14% fire rate |
| Ceramic Heart | +20 max Life and restore 20 |
| Gyro Soles | +9% speed and shorter dash cooldown |
| Fossil Plating | Incoming damage divided by `1 + 0.18 × stacks` |
| Copper Moss | Heal 1.5 on each kill |
| Ember Engine | Hits burn for 2 damage per tick per stack |
| Storm Coil | +18 points chain chance (max 75%); stacks add chain targets |
| Oracle Prism | +8 points double-damage chance (max 60%) |
| Echo Circuit | +12 points extra-shot chance (max 80%) |
| Forked Antenna | Two side bolts; stacks raise their damage (max 75% of the main bolt) |
| Winter Flywheel | Dash slows enemies within six units; stacks extend the duration |
| Salvager's Charm | +2.5 points enemy part drop chance |

Try rapid fire with Ember Engine and Storm Coil for constant hit effects, or splash with Sunken Lens for crowds. Copper Moss and Fossil Plating make a forgiving exploration build.

## Progression

**Accounts (browser + Windows, when the server enables them):** open the title's Account panel to sign in or play as Guest. Cloud records, Zenny, discoveries and Workshop purchases follow your account. Results that cannot sync remain pending and cannot be spent. Retry reconnects safely. Windows sign-in uses a code approved in your browser; the token stays in memory, so sign in again after closing the game. Guest progress remains on this device, separate from cloud progress. Adoption into an empty account needs preview and confirmation; save codes cannot replace an established cloud wallet. Sign-in/out and import are blocked during a dig or lobby.

Every dig starts at level one with no parts. Run levels, upgrades and fitted parts reset; records, unlocks and Workshop purchases persist.

**Zenny** is awarded once at the end of a dig: **25 × depth reached + 60 × guardians defeated + floor(leftover scrap / 5)**.

**Workshop** (title or results screen): each digger has their own 12-circuit grid. Reinforced Frame is the start; after that, buy any circuit linked to one you already own, so you choose the route while every circuit stays reachable. The grid has Lightweight Joints (+4% speed), Salvage Research (early access to a themed part), Shock Plating (+0.2 s protection after a hit), Dash Servos (dash recharges 0.12 s sooner), Tuned Barrel (+6% damage), Scrap Magnet (pickups drift from 40% farther), the Signature Circuit and Signature Circuit II (the digger's ability, then a stronger version), Master Mechanic and Quick Loader (+5% attack speed each) and Reserve Cell (+6% base Life). Two specialization circuits (600 Zenny each) sit at the grid's ends. Owning one unlocks it; equip one per digger for your next dig by selecting it again in the Workshop (select again to unequip). Only the equipped specialization applies, and you can switch freely between digs. Mega: **Focus Lens** (repeated hits on one machine ramp to +40%) or **Ricochet Coil** (hits bounce to a second machine for 60%). Roll: **Field Medic** (out of combat, she and nearby teammates repair 2 Life/s) or **Needle Storm** (held fire ramps to +30% attack speed; every 6th needle exposes a machine to +20% damage from everyone). Tron: **Siege Breaker** (direct hits +40% and stagger) or **Wide Barrage** (+1.5 m blasts that splash harder and slow). Servbot: **Demolition Charge** (+45% bombs, more against guardians) or **Scrap Runner** (dashing drops a bomb; Servbot's kills drop extra scrap). Costs run from 100 to 600 Zenny (4,320 for a full grid), and purchases take effect next dig. Use arrows / D-pad to move, Enter / A to buy, Z / X or the mouse wheel to zoom, and drag to pan; C / Y or LB / RB switch digger.

**Part unlocks** come from lifetime machine kills:

| Total kills | Unlock |
|---|---|
| 0 | Six base parts and all four signature attacks |
| 40 | Ember Engine, Storm Coil |
| 100 | Oracle Prism, Echo Circuit |
| 220 | Forked Antenna, Winter Flywheel, Salvager's Charm |

Saves from earlier builds keep every unlock they had already earned.

**Saving.** Progress saves on every purchase and at the end of each dig (death, extraction or **End Run & Record Discoveries**); discoveries save when a part is fitted. Solo digs don't save mid-run; online digs keep rejoin checkpoints. The browser saves to IndexedDB with a local recovery copy. On Windows the source launcher uses `save/archive.json` and the portable build `build/save/archive.json`; they are separate profiles.

**Save Codes / Backup** (in the Workshop) exports records, discoveries, Zenny and all four trees as a code. Paste a code to preview it, then explicitly replace local progress. Damaged codes change nothing. Leave online play and resolve any saved dig before importing. Settings and active checkpoints aren't included.

## Online co-op

Up to four diggers in the browser or the Windows build. **Play Online** creates a public or private lobby, lists open lobbies or joins by code; **Copy Invite Link** opens the game straight into your lobby, and friends can join a dig already underway.

The run is shared (same ruins and robots, shared scrap and experience) while builds are personal: every cache, guardian core and guardian milestone gives each digger their own pick. When a teammate opens a cache, your pick waits until you press **Tab / Select**, and online you can put a pick aside to finish a fight. Everyone shares one map, which also marks part caches. Robots scale with party size. A digger at 0 Life goes down until a teammate stands beside them; the dig ends only when everyone is down, and the lift waits for the team. Online menus don't pause. Refreshes, crashes, dropped connections and a leaving host don't end the dig. Hosts can remove players, lock the lobby or set a password.

Hosting it on your own domain (Docker Compose + Cloudflare Tunnel, or **Host-Online.cmd**) and the full rules are in [docs/ONLINE.md](docs/ONLINE.md).

## Options

Sound (Master, Music, Effects, Ambience), display (fullscreen, camera motion, field of view), the ruins map (whole-floor survey or a scrolling 80 m local view) and controls (mouse sensitivity, look speed, invert, vibration, rebinding). Settings save separately from progress.

## For developers

- Game direction: [DESIGN.md](DESIGN.md). Current status and how to work on the project: [HANDOFF.md](HANDOFF.md), then the relevant [subsystem handoff](docs/handoff/README.md). Upcoming features: [docs/handoff/ROADMAP.md](docs/handoff/ROADMAP.md).
- Architecture, file responsibilities, tuning knobs, test suites and export commands: [docs/handoff/TECHNICAL.md](docs/handoff/TECHNICAL.md). Latest validation: [docs/FEATURE-REPORT.md](docs/FEATURE-REPORT.md).
- Build history: [CHANGELOG.md](CHANGELOG.md).
- Repository: https://github.com/Alialhashemi23/Megaman-Legends-Rogue. Personal saves, import caches, local backups and raw video captures are ignored by Git. No public release is configured.

Quick checks with the console engine (they don't touch your profile):

```powershell
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --smoke-test
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --combat-test
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --movement-test
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/combat_checks.gd
```

## Prototype scope

A playable prototype with a complete start-to-extraction loop, not a finished game. There is no authored story or surface hub, guardians share a base silhouette, and balance needs human playtesting. See [PLAYTEST-ROADMAP.md](docs/handoff/PLAYTEST-ROADMAP.md).

## Credits and licensing

- Original code and locally authored assets are MIT licensed ([LICENSE.md](LICENSE.md)).
- Mega Man Volnutt, Roll Caskett, Tron Bonne, the Servbots and Mega Man Legends belong to Capcom. The supplied character meshes, textures and skeletons (and portraits rendered from them) are excluded from the MIT license; provenance and credits are in `assets/characters/CREDITS.md`. The twelve animation clips are newly authored; the source archives contain none.
- Music and effects are original, rendered with GeneralUser GS 2.0.3 by S. Christian Collins via FluidSynth; Godot plays the finished files. No original Mega Man music, sound or animation is included. Sources and credits: `assets/audio/AUDIO-NOTES.md`, `tools/audio/`.
- Fonts: Russo One and Barlow Semi Condensed SemiBold, bundled with their SIL Open Font License notices in `assets/fonts/`.
- Godot's license: [GODOT-LICENSE.txt](GODOT-LICENSE.txt).
