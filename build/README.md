# Relic Diver — The Tidal Archive

A local, third-person 3D dungeon roguelike fan prototype made in Godot 4.7.1. Its inspiration is Mega Man Legends and the growing item combinations of action roguelikes. Play as helmet-off Mega Man Volnutt or Roll Caskett using the original PS1 models and textures supplied from The Models Resource. Both have skeletal animation and a left-arm buster. Supporting environment art, music compositions, sound effects and ambience were authored locally.

## Design and handoffs

The intended experience is documented in [DESIGN.md](DESIGN.md). Start a new coding session with [HANDOFF.md](HANDOFF.md), then read only the relevant [subsystem handoff](docs/handoff/README.md). These cover technical setup, art/animation, audio/UI, playtest priorities and repository packaging.

The user authorized this repository after the initial local-only development: https://github.com/Alialhashemi23/Megaman-Legends-Rogue. The user later requested browser co-op hosted on their own domain; the server and deployment files are included, and the user runs the deployment. No public release is configured. Personal saves, import caches, historical backups and raw video captures remain local and are ignored by Git.

## Online co-op pass 09

Play in the browser with up to four diggers. Choose **Play Online** on the title screen to create a public or private lobby, browse open lobbies, or join by code. **Copy Invite Link** gives friends a link that opens the game straight into your lobby. Friends can also join a dig already in progress.

Everyone shares the run: the same ruins and robots, shared scrap and experience. Builds are personal: each cache offers every digger their own part, and each guardian drops a core per digger. Robots grow tougher with each digger. A digger at 0 Life goes down; stand beside them to revive them, and while down you watch a teammate. The dig ends only when the whole team is down, and the lift waits for everyone. Online menus don't pause the action. Chat with T, ping with G and use 1–4 for quick callouts. Hosts can remove players, lock the lobby or set a password.

Pass 11 adds full controller support, an **Options** menu (sound, display, sensitivity, invert look, vibration and full key/button rebinding) and **Leave Dig** in the pause menu for every player. Online, a host who leaves hands the dig to the others. Solo digs are short and don't save mid-run.

Runs are protected against mishaps (pass 10): a refresh, crash or dropped connection brings you back into the same dig with your exact build; if the host leaves, hosting moves to another player; if everyone drops out, the server holds the dig for 15 minutes; and every browser keeps its own checkpoint, so even a server restart can be resumed with **Rejoin Dig**. (Solo digs don't save mid-run as of pass 11.)

To host it on your domain, see [docs/ONLINE.md](docs/ONLINE.md): `docker compose up -d --build` with a Cloudflare Tunnel token, or **Host-Online.cmd** without Docker. The web bundle is `build/RelicDiver-Web.zip`; rebuild it with `tools/package-web.ps1` or `tools/package-web.sh`. Implementation notes are in [docs/handoff/NETWORK.md](docs/handoff/NETWORK.md).

On a fresh Windows clone, double-click Play.cmd or Edit.cmd. The launcher extracts the tracked build/RelicDiver-Windows.zip and prepares the pinned Godot runtime if necessary. Alternatively, extract that ZIP to a folder and run RelicDiver.exe. Keep the executable, pack and notices together. The original PC's existing runtime and saves are preserved.

## Motion pass 07

Mega and Roll now use compact, springy running cycles with distinct contact, push-off and recovery poses. Bent knees and rolling boots replace the mirrored marching motion. Shoulder and pelvis movement stays restrained to suit the original Legends models. The converter fits body height to each model's actual boot soles.

Run, backpedal and strafe transitions preserve the current step. Footstep sounds follow the animation contacts, and torso compensation keeps the buster steady while the body moves. Movement, jump and dash controls remain responsive. These are newly authored animations inspired by Legends; the supplied archives contain no original animation clips. The previous character pass is preserved in `backups/v6/`.

## Tron Bonne and Servbot (pass 15)

Tron Bonne and a Servbot are playable alongside Mega and Roll, built from the user's supplied Legends models. **C** (or **Y** on a controller) cycles through all four on the title screen. They share the same statistics, busters, parts and progression for now. See `assets/characters/CREDITS.md`.

## Character pass 06

The procedural player has been replaced with the supplied original Legends model. Roll is a second playable digger. Choose **Mega** or **Roll** on the title screen, or press **C** to switch the preview. Both share the same statistics, weapons, unlocks, loot and progression; selection remains active across descents.

Both retain their original 18-joint skins and painted texture atlases. Twelve new clips cover idle, running, backpedal, strafing, jump/fall, dash, damage, firing, victory and defeat. Aiming and recoil layer onto the buster arm while the legs continue running. The muzzle position comes from that animated arm. The left glove is replaced by an attached cannon to prevent mesh intersections. Roll uses her more detailed cutscene mesh and a red cannon.

The HUD and pause menu show the selected character's name and portraits rendered from the imported models. Editable GLB files are in `assets/characters/`; unmodified source archives, a repeatable converter and hashes are in `tools/model-sources/`. Model credits are in `assets/characters/CREDITS.md`. These Capcom assets are excluded from the original-code MIT license. The previous version is preserved in `backups/v5/`. Everything remains local.

## Audio pass 05

Seven original music cues now cover the title, each of the three descents, guardians, extraction and defeat. The sampled electric piano, bells, marimba, guitars, bass and percussion use GeneralUser GS 2.0.3 by S. Christian Collins, rendered locally with FluidSynth. Godot plays the finished files and needs no audio middleware or SoundFont installed. Guardians trigger a battle theme; music crossfades and lowers during menus and part choices.

There are 29 original sound effects: distinct Pulse, Needle and Siege busters, varied metal impacts and footsteps, jump/landing, dashes, robot weapons and destruction, attack warnings, scrap, healing, parts and menu cues. Robot effects have 3D positioning. A quiet ventilation and resonant machinery loop fills the ruins. No original Mega Man music or game sound files were used.

Pause → **Options** (pass 11; formerly Sound Settings) adjusts Master, Music, Effects and Ambience separately. Use arrows to select/adjust, or click a row. **M** toggles all sound. Settings save locally in `save/audio.json`; they do not change your run records. The local build has been updated. Full sources, editable MIDI scores and a soundtrack preview are in `tools/audio/`; see `assets/audio/AUDIO-NOTES.md` for credits and implementation details.

## Historical visual pass 02

The initial block character has been replaced with a segmented low-poly Volnutt fan model. Running now includes a swinging free arm and body lean; aiming and recoil use the left buster. The follow camera sits over the left shoulder to match the firing position.

Five editable 128 × 128 SVG texture sources live in `assets/textures/`: painted masonry, stone floor, weathered metal, blue armor, and the character face. Godot rasterizes them on import and samples them with nearest filtering. No artificial screen wobble or forced low-resolution filter is applied.

Rooms now have ceilings, ceiling beams, warm interior lamps, painted masonry walls, metal door frames, and inlaid floor paths. Enemy bodies are more rounded and have mechanical eye details. The title camera shows the playable character inside the landing chamber.

The previous scripts and playable content pack are preserved in `backups/v1/`. No Git repository, upload, or publishing step was used. This historical pass used locally authored characters; pass 06 above replaces them with the supplied game assets.

## Combat and exploration pass 03

Enemy attacks now have distinct windups and recovery windows. Melee robots mark a swing arc, sentries show a committed aim line, and armored machines mark a charge lane before rushing. Aim lines stay fixed once the windup starts, giving you time to move away. Attacks pause with the game.

Each guardian has its own attack mix:

| Descent | Guardian | Attacks |
|---|---|---|
| 1 | Archive Keeper | Fan bursts and a nearby ground shockwave |
| 2 | Verdant Engine | Three marked bombardment circles, fan bursts, and a nearby shockwave |
| 3 | Core Warden | Crossing beam lanes, wider fan bursts, and a nearby shockwave |

Leave marked danger zones before the windup finishes. Jump above ground shockwaves, or use dash invulnerability. Solid cover blocks melee attacks, shockwaves, beams, and Siege Buster splash. At half health, guardians enter overdrive after a short recovery window.

Buster feedback now includes a muzzle flash at the actual barrel, short bolt trails, recoil, confirmed-hit crosses, enemy hit flashes, small knockback, kill confirmation, and impact rings. Siege shots also splash exposed enemies when they hit a wall. The pause menu can disable camera effects. Lock-on releases after a target stays behind cover for 0.75 seconds.

Ordinary chambers now use five arrangements: Pillar Gallery, Relay Chamber, Salvage Archive, Coolant Works, and Broken Foundry. These change cover positions and sightlines while keeping doors accessible. A grid pathfinder gives robots routes around cover and between connected rooms. The current chamber's name appears in the HUD.

The prior visual-pass version is preserved locally in `backups/v2/`. Current staged attack and room previews are in `screenshots/`.

## Play

Double-click **Play.cmd** in this folder. No installation, account, network connection, Blender, or additional asset downloads are required.

Alternatively, double-click **build/RelicDiver.exe**. Keep **RelicDiver.pck** next to that executable. The portable build includes the Godot runtime in its executable, which makes it larger than a normal release-template export.

Double-click **Edit.cmd** to open the editable project in the bundled Godot editor. The entry point is `project.godot`; all gameplay lives in `scripts/`.

## UI pass 04

The interface now follows the visual language of console adventure menus: framed cobalt windows, a blue mechanical background pattern, shaded cream lettering, a yellow selection cursor, and green segmented Life meters. The title screen, combat HUD, pause menu, equipment list, part choices, collection, and results screen all use the same spacing and palette.

Russo One provides the heavy display lettering and counters. Barlow Semi Condensed SemiBold provides the menu text and descriptions. Both font files are bundled locally, with their SIL Open Font License notices in `assets/fonts/`. No system font installation or runtime download is needed.

The hand-drawn icon atlas contains 32 equipment and status icons, including a distinct icon for each of the thirteen parts and each buster. The UI also includes a locally drawn Volnutt portrait. Menu copy uses Life, Buster Parts, and Dig terminology. Fitted parts show their stack count and combined effect. The equipment panel reports the current buster's actual shot power, including its weapon multiplier.

Use arrow keys to browse menus and part lists, Enter to confirm, and Escape to return. Mouse selection and the existing 1/2/3 upgrade shortcuts work too. Scroll the parts list with the mouse wheel. The combat view keeps most of the center clear, with a vertical Life gauge, small buster panel, part icons, and a framed ruins map.

UI elements scale uniformly rather than stretching text and icons. Widescreen views expand the game view while keeping the interface inside a centered safe area. Inventory, pause, results, and HUD previews are in `screenshots/ui-*.png`. Preview images use staged equipment and stats; they do not change your save.

The previous combat-pass scripts, assets, and content pack are preserved in `backups/v3/`.

## Controls

| Input | Action |
|---|---|
| WASD | Move relative to the camera |
| Mouse | Free aim / rotate camera |
| Hold left mouse | Fire the buster |
| Q or right mouse | Toggle lock-on to a visible nearby enemy |
| Left Shift | Dash with a short invulnerability window |
| Space | Jump |
| E | Open a cache, salvage a vessel, use a well, or activate a lift |
| Tab | Inspect your relics and current stats; pauses the game |
| Escape | Pause / resume |
| 1, 2, 3 | Pick an upgrade on a choice screen |
| M | Mute / unmute sound and ambience |
| Enter | Start a run from the title or results screen |
| Arrow keys | Browse menu options and equipment |
| Enter in a menu | Confirm the highlighted option |
| Mouse wheel in equipment / collection | Scroll through parts |

## Your first descent

1. Choose the Pulse Buster and begin. Approach the golden starter cache on your left and press E for a free relic.
2. Follow doorways into connected chambers. The survey map reveals adjoining rooms as you explore. The guardian chamber gets a gold outline once discovered nearby.
3. Shoot the machines, dash through attacks, and collect their scrap and experience. Nearby drops move toward you automatically.
4. Clear a room to unlock its cache and earn five bonus scrap. Spend scrap on a choice of three relics or save it for a restoration well. Vessels contain free salvage. Use cover to break enemy aim and watch the ground warnings before committing to a fight.
5. Leveling pauses combat for a choice of damage, health, or fire-rate upgrades.
6. Defeat the Archive Keeper to power the lift. You can still explore other chambers before leaving. Lifts preserve the run's build and restore 25% health.
7. Survive three descents and activate the final extraction beacon to win.

There is no countdown or time-based difficulty escalation. Explore at your own pace. Difficulty increases with descent depth.

## Content

- Three ruin palettes: Tidal Archive, Garden of Engines, Heart of the Machine.
- Connected, seeded layouts of 8, 9, and 10 rooms joined by corridors and passages that fork, loop back or dead-end at hidden salvage, with cover and a guardian room.
- Special chambers: a two-cell Grand Concourse with a colonnade and raised dais, a Stepped Vault jump puzzle with a free cache on its ledge, and a Terrace Hall whose high ground is reached by ramps (robots use the ramps too).
- Chase robots, floating ranged sentries, charging armored machines, and three guardian attack patterns with overdrive phases.
- Five room arrangements with different cover, machinery, shelves, tanks, and sightlines.
- Thirteen stackable relics, three busters, experience levels, scrap, healing wells, paid caches, enemy drops, and salvage vessels.
- Camera collision, free aim, optional line-of-sight lock-on, animated segmented characters, painted low-resolution textures, enclosed and lit ruins, hit feedback, particles, damage numbers, audio, map, inventory, archive, pause screen, and run results.

## Persistent progression

Every run starts at level one with base stats and no relics. Lifetime machine kills unlock new drops and weapon choices for subsequent runs. Merely unlocking an item does not add it to your starting inventory.

| Total kills across completed / ended runs | Unlock |
|---|---|
| 0 | Six base relics and Pulse Buster |
| 10 | Ember Engine, Storm Coil, Needle Buster |
| 25 | Oracle Prism, Echo Circuit |
| 50 | Forked Antenna, Winter Flywheel, Salvager's Charm, Siege Buster |

Discoveries save when a relic is installed. Kill totals, wins, and run records save on death, extraction, or **End Run & Record Discoveries** in the pause menu. Closing the window during a run does not record that run's kills. There is no mid-run resume yet.

The source launcher saves in `save/archive.json`. The portable executable saves in `build/save/archive.json`. These are independent profiles; copy the JSON between them if you switch versions. The file is plain JSON and can be backed up. Saves remain on your computer.

## Relics and combinations

| Relic | Effect per stack |
|---|---|
| Sunken Lens | +16% damage |
| Clockwork Spring | +14% fire rate |
| Ceramic Heart | +20 max health and restore 20 |
| Gyro Soles | +9% speed and reduced dash cooldown |
| Fossil Plating | Incoming damage divided by `1 + 0.18 × stacks` |
| Copper Moss | Heal 1.5 on each kill |
| Ember Engine | Hits burn for 2 damage per tick per stack |
| Storm Coil | +18 percentage points chain chance, capped at 75%; stacks add chain targets |
| Oracle Prism | +8 percentage points double-damage chance, capped at 60% |
| Echo Circuit | +12 percentage points extra-shot chance, capped at 80% |
| Forked Antenna | Two side bolts; stacks raise their damage, capped at 75% of the main bolt |
| Winter Flywheel | Dash slows enemies within six units; stacks extend duration |
| Salvager's Charm | +2.5 percentage points enemy relic drop chance |

Try Needle Buster with Ember Engine and Storm Coil for frequent hit effects, or Siege Buster with Sunken Lens for crowd damage. Copper Moss and Fossil Plating support a more forgiving exploration build.

## Project layout

- `scripts/game.gd`: dungeon generation, encounters, drops, progression, persistence, run state, validation modes.
- `scripts/player.gd`: movement, dash, camera, aiming, busters, character animation, stats.
- `scripts/enemy.gd`: robot behavior, guardian, damage, item hit effects.
- `scripts/navigation.gd`: traversable dungeon grid and routes around cover.
- `scripts/bolt.gd`: swept projectile collisions and splash damage.
- `scripts/art.gd`: modular meshes, Volnutt fan model, robot construction, materials, and texture application.
- `assets/textures/`: editable painted SVG texture sources, rasterized by Godot on import.
- `scripts/hud.gd`: resolution-scaled menus, inventory, map, and HUD.
- `assets/ui/`: original painted icon atlas, portrait, and blue menu pattern.
- `assets/fonts/`: bundled display and menu fonts plus their license notices.
- `scripts/sound.gd`: synthesized effects and looping ambience.

## Verification

The build was imported and run with the bundled engine. Automated checks cover generation connectivity, relic stacking, cache choices, damage, experience, upgrades, floor transitions, extraction, projectile collisions with a moving enemy, hostile projectile damage, physical keyboard movement through a doorway and corridor, and save/load persistence. Title, gameplay, choice screens, guardian warnings, and room layouts were rendered and visually inspected at 1280 × 800 on the local GPU.

The additional behavior suite checks six generation seeds, reachability around all five cover arrangements, enemy spawns, harmless windups, successful dodges, committed ranged aim, charging, bombardment, cross beams, jumping over shockwaves, dash invulnerability, melee and splash obstruction, overdrive cancellation, enemy pursuit around an obstacle, and paused warning timers. It uses an isolated scene and does not write a player profile.

The UI suite checks menu actions, keyboard navigation, empty and full inventories, scrolling all thirteen parts, mouse targets after resizing, upgrade confirmation, number shortcuts, and locked collection entries. UI renders were inspected at 960 × 600, 1280 × 800, and 1920 × 1080.

Run the checks with the console engine:

```powershell
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --smoke-test
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --combat-test
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --movement-test
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --persistence-test
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/combat_checks.gd
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/ui_checks.gd
```

The first three do not save a player profile. The persistence test uses a separate temporary validation file and removes it on success.

## Prototype scope

This is a playable prototype with a complete start-to-extraction loop. Mega and Roll use the supplied original meshes, textures and skeletons with newly authored animation clips and a runtime buster aiming layer. The three guardians share a base silhouette with different palettes and attack mixes. Enemy navigation uses a flat dungeon grid; dynamic crowd avoidance and more elaborate vertical traversal remain future improvements. Balancing needs human playtesting. Later passes added online co-op (09–10) and controller support with an Options menu (11); there is still no authored story.

The next development pass should use human playtest feedback to tune movement, attack timing, progression, room density, and readability. Distinct boss silhouettes, environmental puzzles, and mid-run resume are useful subsequent improvements. Original code and locally authored assets are MIT licensed; the supplied Capcom character meshes, textures and skeletons are excluded. See LICENSE.md. Godot's license notice is in GODOT-LICENSE.txt. Mega Man Volnutt, Roll Caskett and Mega Man Legends belong to Capcom. No original-game music, sound effects or animation clips are included.
