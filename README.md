# Relic Diver — The Tidal Archive

A third-person 3D dungeon roguelike fan prototype made in Godot 4.7.1, inspired by Mega Man Legends and the stacking item combinations of action roguelikes. Play as helmet-off Mega Man Volnutt, Roll Caskett, Tron Bonne or a Servbot, using the original PS1 models and textures supplied from The Models Resource. Explore seeded ruins alone or with up to three friends online. Environment art, animation, music, sound effects and ambience were authored for this project.

> **Fan project notice:** Relic Diver is a free, non-profit fan game. It is not affiliated with, endorsed by or sponsored by Capcom. Mega Man Legends, Mega Man Volnutt, Roll Caskett, Tron Bonne and the Servbots, and their original models and textures, belong to Capcom; they are excluded from this project's MIT license. Nothing here is sold, and it will never be monetized. Rights holders can reach the maintainer through GitHub. See [Credits and licensing](#credits-and-licensing).

## Download for Android

**Current release: Android 0.21.0 (version code 7), matching build 35 and co-op protocol 12.**

**[Download the latest APK](https://github.com/Alialhashemi23/Megaman-Legends-Rogue/releases/latest/download/RelicDiver-android.apk)** (Android 7.0 or newer, 64-bit ARM; about 31 MB). All versions and release notes: [Releases](https://github.com/Alialhashemi23/Megaman-Legends-Rogue/releases).

Built for handhelds with controllers (such as the Retroid Pocket 5); a gamepad or a Bluetooth controller is needed, as there are no touch controls.

**Install**

1. On the device, open the download link above in the browser (or copy the `.apk` over USB to its **Download** folder).
2. Open the downloaded `RelicDiver-android.apk` from the browser's downloads or the **Files** app.
3. If Android asks, allow installs from that app (**Settings → Allow from this source**), then go back and tap **Install**.
4. If Google Play Protect warns that the app is unrecognised, choose **More details → Install anyway**. It warns because the game isn't distributed through the Play Store.
5. Open **Relic Diver**. Play as Guest, or sign in from the account bar on the title screen to sync progress with the browser and Windows versions.

**Updating:** download the newer APK and install it over the existing app; saves and sign-in are kept. Updates must be signed with the same key as the installed version.

**Check the file (optional):** each release lists the APK's SHA-256. The signing certificate's SHA-256 is `e3:9e:37:ab:31:0d:cc:d8:df:bf:d7:0f:3b:f9:0c:41:30:6e:0e:79:70:40:b7:77:c0:12:12:d7:01:3c:fc:ab` (check with `apksigner verify --print-certs RelicDiver-android.apk`).

**Upgrading from a pre-release test build** (0.19.0 test builds and earlier, signed with a different key): uninstall the old app first. Account progress is on the server and comes back when you sign in; Guest progress on that device is lost.

## Play

- **Browser:** https://megaman.galosengen.dev (desktop Chrome, Edge, Firefox or Safari).
- **Windows, from this folder:** double-click **Play.cmd**. On a fresh clone it extracts the tracked `build/RelicDiver-Windows.zip` and prepares the pinned Godot runtime first. No installation, account, network connection or extra downloads are needed for solo play.
- **Portable:** extract `build/RelicDiver-Windows.zip` and run **RelicDiver.exe**, keeping `RelicDiver.pck` and the notices beside it. The executable is the full Godot runtime, so it is larger than a normal release export.
- **Android:** see [Download for Android](#download-for-android). To build it yourself, `tools/package-android.ps1` makes a debug-signed ARM64 APK (`-Release` signs with your own keystore from environment variables). See [Android updates](docs/ANDROID-UPDATES.md). Credits / Licenses is available from the title.
- **Edit:** **Edit.cmd** opens the project in the bundled editor. The entry point is `project.godot`; gameplay lives in `scripts/`.

## Diggers

| Digger | Signature attack | Notes |
|---|---|---|
| Mega | Pulse Buster, the all-rounder | |
| Roll | Rapid Needle Buster | Revives teammates twice as fast |
| Tron | Heavy Siege Buster with cover-aware splash | |
| Servbot | Arcing salvage bombs | 65 base Life, 18% faster, smaller hitbox and lower camera |

Press **C** (controller **Y**) on the title screen to cycle diggers. Each has their own Workshop tree (see [Progression](#progression)).

**Solo** opens preparation: left/right chooses a digger; confirm the selection, then press again on **Start Dig**. Online, everyone selects **Ready** before the host starts the cancellable countdown. Current browser/Windows co-op uses game protocol 12; older Android APKs need a matching update to join these lobbies.

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
| Buster parts and stats (pauses solo); opens waiting upgrades first | Tab | Select / View |
| Pause / menu | Backquote / tilde (` / ~) | Start |
| Pick an upgrade on a choice screen | 1, 2, 3 | D-pad / stick + A |
| Reroll a part or milestone offer (once per descent) | R | Y |
| Ping (online) | G or middle mouse | LB |
| Chat (online) | T or Enter | — |
| Quick callouts (online) | 1–4 | D-pad |
| Switch digger (title) | C | Y |
| Mute | M | — |

Menus: arrows or the mouse to browse, Enter to confirm, Escape to go back (controller: D-pad or left stick, A, B). The mouse wheel scrolls part lists.

Upgrade choices appear over the current game view. Solo pauses; in co-op, earned part, level and milestone choices wait until opened with Tab / Select. Your digger stands still and remains vulnerable while choosing online. Each pick needs a fresh press; Esc / B keeps unused offers for later. Exact waiting offers survive rejoining; unpicked upgrades expire at final extraction. Each digger has **one reroll per descent** for a part or milestone offer (not level-ups).

**Options → Controller test** shows what the game sees from your pad (name, axes, buttons, browser mapping) without changing bindings. **Dig ended → Dig Log** keeps your last 20 digs on this device: your build at each guardian, the fight length, Life lost and every pick.

## Your first descent

1. Pick a digger and begin. Open the golden starter cache on your left with E for a free part.
2. Follow doorways into connected chambers. The ruins map reveals rooms as you explore and outlines the guardian chamber in gold once you're nearby.
3. Shoot the machines, dash through attacks and collect their scrap and experience. Nearby drops move toward you.
4. Clear a room to unlock its cache and earn five bonus scrap. Spend scrap on a choice of three parts, or save it for a restoration well. Vessels hold free salvage.
5. Levelling up offers a choice of damage, Life or fire-rate upgrades. A power pick counts like one more Sunken Lens and a fire-rate pick like one more Clockwork Spring.
6. Defeat the guardian to power the lift. You can keep exploring first. Lifts keep your build and restore 25% Life.
   The first and second guardians also give each digger a **guardian milestone**: a choice of three major upgrades for the rest of the dig, weighted toward parts you have fitted (each also works without them). They are Arc Conductor, Wildfire Core, Glacier Drive, Twin Capacitor, Fortune Prism, Bulwark Frame, Scavenger's Instinct, Opening Salvo, Second Wind and Kinetic Loader. The final guardian ends the dig, so it gives its part reward only. Regular parts and level-ups still stack as before.
   Guardians vent a glowing **core** on their back after big attacks: hits there deal far more damage for a few seconds. At half Life they shield briefly and call for helpers. The last guardian's arena has stone pillars that block its shots until they crumble.
7. Survive three descents and activate the extraction beacon to win.

From the second descent, **Grenadiers** lob shell volleys over cover (keep moving) and **Menders** repair nearby machines (shoot them first). Each floor also has a **Power Relay** chamber: activate the console, then stand in the lit ring while machines pour in. When it's charged, the vault gives every digger a better part pick.

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

**Accounts (browser, Windows and Android, when the server enables them):** press the title's account bar to open the sign-in panel over the title: email and password, then a 6-digit code if your account uses an authenticator app. Create an account or reset a forgotten password from the same panel (the confirmation and reset links arrive by email). Cloud records, Zenny, discoveries and Workshop purchases follow your account. Results that cannot sync remain pending and cannot be spent. Retry reconnects safely.

Guest progress and accounts: if you play as Guest and then create an account, your Guest progress moves into the new account and continues there. Signing in to an account that already has progress keeps the account's progress, and this device's Guest progress (including a saved Guest dig) is discarded. Browsers stay signed in as long as you play at least once a week; Android remembers your sign-in securely; Windows keeps it in memory, so sign in again after closing the game. Save codes cannot replace an established cloud wallet. Sign-in/out and import are blocked during a dig or lobby.

Every dig starts at level one with no parts. Run levels, upgrades and fitted parts reset; records, unlocks and Workshop purchases persist.

**Zenny** is awarded once at the end of a dig: **25 × depth reached + 60 × guardians defeated + floor(leftover scrap / 5)**.

**Workshop** (title or results screen): each digger has their own 12-circuit grid. Reinforced Frame is the start; after that, buy any circuit linked to one you already own, so you choose the route while every circuit stays reachable. The grid has Lightweight Joints (+4% speed), Salvage Research (early access to a themed part), Shock Plating (+0.2 s protection after a hit), Dash Servos (dash recharges 0.12 s sooner), Tuned Barrel (+6% damage), Scrap Magnet (pickups drift from 40% farther), the Signature Circuit and Signature Circuit II (the digger's ability, then a stronger version), Master Mechanic and Quick Loader (+5% attack speed each) and Reserve Cell (+6% base Life). Two specialization circuits (600 Zenny each) sit at the grid's ends. Owning one unlocks it; equip one per digger for your next dig by selecting it again in the Workshop (select again to unequip). Only the equipped specialization applies, and you can switch freely between digs. Mega: **Focus Lens** (repeated hits on one machine ramp to +40%) or **Ricochet Coil** (hits bounce to a second machine for 60%). Roll: **Field Medic** (out of combat, she and nearby teammates repair 2 Life/s) or **Needle Storm** (held fire ramps to +30% attack speed; every 6th needle exposes a machine to +20% damage from everyone). Tron: **Siege Breaker** (direct hits +40% and stagger) or **Wide Barrage** (+1.5 m blasts that splash harder and slow). Servbot: **Demolition Charge** (+45% bombs, more against guardians) or **Scrap Runner** (dashing drops a bomb; Servbot's kills drop extra scrap). Costs run from 100 to 600 Zenny (4,320 for a full grid), and purchases take effect next dig. Use arrows / D-pad to move, Enter / A to review a purchase, Z / X or the mouse wheel to zoom, and drag to pan; C / Y or LB / RB switch digger.

Purchases show the circuit or specialization, its effect, cost and wallet before/after. Cancel is selected first; spending requires a fresh Confirm. Back returns to the same node. After submitting an account purchase, Close leaves it pending; Retry Sync uses the same transaction. Equipping an owned specialization stays free.

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

**UI / text preset** switches between Standard and Handheld. Handheld uses larger copy, taller title actions, wider upgrade cards and a roomier Workshop description panel. **Minimap size** is independent of whole-floor/follow zoom. **Camera framing** independently offers Standard or Close; Standard keeps the original PC view. These preferences stay on this device/browser and do not change your account or Ready loadout. Fresh Android installs select Handheld and Large map; existing settings keep their prior layout until you choose otherwise. Retroid physical readability and controller checks remain pending.

## For developers

- Game direction: [DESIGN.md](DESIGN.md). Build history: [CHANGELOG.md](CHANGELOG.md). Latest validation notes: [docs/FEATURE-REPORT.md](docs/FEATURE-REPORT.md).
- Hosting and accounts: [docs/ONLINE.md](docs/ONLINE.md), [docs/ACCOUNTS-OPS.md](docs/ACCOUNTS-OPS.md), API contract [docs/ACCOUNT-API.md](docs/ACCOUNT-API.md), Android updates [docs/ANDROID-UPDATES.md](docs/ANDROID-UPDATES.md).
- Layout: `scripts/` holds the game (`game.gd` run loop and online play, `player.gd`, `character.gd` animation and aim, `enemy.gd`, `ruins.gd` generation, `hud.gd` menus, `account.gd` sign-in and sync, `net.gd` co-op, `progression.gd` Workshop grids). `server/` is the Node lobby relay, static host and account API (Better Auth + PostgreSQL). `tools/model-sources/build_characters.py` converts the character sources and authors their animation clips; `tools/audio/` composes and renders the music. `tests/` holds the check scripts.
- Engine: Godot 4.7.1. On Windows, `tools/setup-runtime.ps1` (run by Play.cmd) restores the pinned console engine from `build/RelicDiver-Windows.zip`. After changing assets, run `--headless --editor --path . --import` once.
- Personal saves, `.env`, keys, databases, backups, raw captures and local development notes are ignored by Git.

Checks with the console engine (they never touch your own profile):

```powershell
$env:APPDATA = Join-Path (Get-Location) 'tools/runtime'; $env:LOCALAPPDATA = $env:APPDATA
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --smoke-test        # whole loop (also --combat-test, --movement-test, --persistence-test)
.\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tests/character_checks.gd
```

| Area | Checks |
|---|---|
| Characters, motion, aim | `tests/character_checks.gd` |
| Combat | `tests/combat_checks.gd`, `--combat-test` |
| UI, options | `tests/ui_checks.gd`, `tests/options_checks.gd` |
| Progression, Workshop, milestones | `tests/progression_checks.gd`, `tests/milestone_checks.gd` |
| Accounts | `tests/account_checks.gd`; `tests/account_e2e.mjs` with `TEST_DATABASE_URL`, `GODOT` and optionally `PLAYWRIGHT_MODULE` |
| Online co-op, checkpoints | `tests/run_resume_checks.gd`, `tests/coop_feedback_checks.gd`, `tests/net_test.sh <godot>`, `server/` `npm test` |
| Android | `tests/android_checks.gd` |

Builds: `tools/package-web.ps1` (browser bundle), `--export-pack 'Windows Desktop' build/RelicDiver.pck` then `tools/package-windows.ps1` (portable ZIP), `tools/package-android.ps1` (APK; `-Release` with your own keystore via `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD`). Run the packaging scripts with your normal `%APPDATA%`, where Godot's export templates live.

## Prototype scope

A playable prototype with a complete start-to-extraction loop, not a finished game. There is no authored story or surface hub, guardians share a base silhouette, and balance needs human playtesting.

## Credits and licensing

- Original code and locally authored assets are MIT licensed ([LICENSE.md](LICENSE.md)).
- Mega Man Volnutt, Roll Caskett, Tron Bonne, the Servbots and Mega Man Legends belong to Capcom. The supplied character meshes, textures and skeletons (and portraits rendered from them) are excluded from the MIT license; provenance and credits are in `assets/characters/CREDITS.md`. The twelve animation clips are newly authored; the source archives contain none.
- Music and effects are original, rendered with GeneralUser GS 2.0.3 by S. Christian Collins via FluidSynth; Godot plays the finished files. No original Mega Man music, sound or animation is included. Sources and credits: `assets/audio/AUDIO-NOTES.md`, `tools/audio/`.
- Fonts: Russo One and Barlow Semi Condensed SemiBold, bundled with their SIL Open Font License notices in `assets/fonts/`.
- Godot's license: [GODOT-LICENSE.txt](GODOT-LICENSE.txt).
