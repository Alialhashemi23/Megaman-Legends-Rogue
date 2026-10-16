# Mega Man Legends Rogue — design direction

Working game title: **Relic Diver — The Tidal Archive**. Repository name: Mega Man Legends Rogue. This is a non-profit fan project inspired by Mega Man Legends, with playable Mega Man Volnutt and Roll Caskett. It is not affiliated with Capcom. See LICENSE.md and asset credits for ownership.

## The experience we want

Explore a mysterious underground machine world as Mega. Turn a modest buster into an unusual build by finding parts that stack and interact. Search branching ruins, read robot attacks, survive a guardian, and decide whether to keep exploring before descending. The appeal is curiosity, readable action and growing combinations, grounded in the colorful PS1 adventure style of Legends.

The user's explicit choices are third-person free aim with optional lock-on; unlock new items and weapons between runs while power resets; colorful ancient machinery and mysterious robots; helmet-off Mega with brown hair and blue armor; low-poly models with painted textures. Roll is a second playable main character. Mega, Roll, Tron and Servbot have signature attacks and individual skill trees.

## Design pillars

1. **Legends atmosphere.** Warm painted stone, colorful mechanical accents, enclosed ruins, expressive silhouettes and friendly adventure energy. Mystery comes from the architecture and machines. Avoid replacing this with a dark military shooter or glossy modern realism.
2. **Dungeon exploration.** Branches, doors, cover, salvage and discoveries should make a chamber worth investigating. There is no time-based difficulty escalation. Descending increases difficulty; exploration can happen at the player's pace.
3. **Buster-first action.** Responsive movement, clear aim and lock-on, readable enemy preparation, and satisfying hit feedback. Movement animations should feel quick, compact and springy like Legends, with restrained sway and a firm firing arm.
4. **Parts that build on each other.** Risk of Rain is the reference for stackable themed drops and combinations. Parts should change decisions and create recognizable builds; it is not a request to copy that game's timer, exact items or presentation.
5. **Fresh runs, broader options.** Run statistics and fitted parts reset. Persistent progression expands each digger's options through a Zenny-funded circuit grid per digger (a Sphere Grid-style network: buy circuits linked to ones you own): signature circuits, early part-pool research, and modest bonuses to Life, speed, attack speed, damage, dashing, protection and pickup reach. Character specializations attach to the grid in P5. Run levels, upgrades and fitted parts reset. All permanent numbers live in scripts/progression.gd; balance remains subject to playtesting.

## Current run loop

Select Mega, Roll, Tron or Servbot with their signature attack → enter a seeded ruin → collect a starter part → explore connected chambers → fight machines and salvage scrap/XP → open caches and choose upgrades → defeat the guardian → explore further or use the lift → repeat across three descents → extract, or record the run on defeat → earn Zenny → develop a digger in the Workshop.

Caches offer choices; healing wells create a competing use for scrap. Experience grants a paused upgrade choice. Parts stack, and combinations can trigger burn, chains, extra shots, splitting bolts, healing and defensive effects. Lifts preserve the current build and restore some Life. Details and current numbers are in README.md and scripts/game.gd; treat those as tunable prototype values.

## Combat and exploration direction

Keep free aim useful and optional lock-on dependable. Telegraph threats before damage: melee arcs, fixed aim lines, charge lanes, bombardment circles, shockwaves and beam lanes. Cover should consistently block attacks that visually hit it. Jumping and dashing need distinct practical uses.

Layouts should offer navigation choices and recognizable chamber functions, not only empty arenas joined by corridors. Pass 12 (user request): rooms are 50% bigger, hallways fork, loop and dead-end, and each floor mixes the five cover arrangements with a big two-cell hall, a jump-puzzle vault and a terraced room with ramps. Robots stay on the ground floor except where ramps lead up. The user also asked for a to-scale map with an exact, camera-facing position arrow. More puzzles, further vertical spaces and more distinct guardians remain possibilities, not settled requirements.

## Art and animation direction

Use the supplied original PS1 character geometry, texture atlases and rigs. Preserve helmet-off Mega's silhouette and Roll's identity. Nearest-filtered painted textures and simple lighting should remain readable. Avoid block-shaped replacement characters, excessive texture detail, gratuitous post-processing and modern material shine.

Original model archives contain no animation clips. The current clips are authored locally. Improve knee bends, foot placement, transitions and personality while preserving the original game's compact energy. Do not pursue exaggerated swagger, slow cinematic inertia or photorealistic motion capture. Aiming must remain steady and projectiles must originate at the animated muzzle.

## UI and audio direction

Menus use cobalt mechanical frames, cream lettering, a yellow selector, green Life segments, illustrated part icons and consistent spacing. Copy should feel like an adventure game: Life, Buster Parts, Dig, salvage and descents. Keep the combat center readable and descriptions useful for choosing builds.

Music should suggest an adventurous late-1990s console world through melodic electric piano, bells, marimba, guitar, bass and restrained percussion. The seven existing cues are original compositions. Ruin ambience and mechanical effects support space and feedback; attacks, pickups and menu actions need distinct sounds. Godot native audio currently handles these requirements.

## Online co-op (accepted, pass 09)

The user asked for seamless browser co-op on their own domain: make a lobby, send friends a link or let them join from a lobby browser, and play together. Accepted choices: up to four diggers; one shared run with personal builds (shared scrap and XP, every digger picks their own part from each cache, one guardian core each); downed diggers are revived by a teammate standing close, and the run ends when everyone is down; open access (public lobbies listed, private lobbies by link/code). Robots scale with party size. Online menus and choices don't pause the dig. Run power still resets; unlocks stay per player.

The user then asked that runs persist through errors and mishaps before further work (pass 10). Accepted: a host leaving never ends the dig (hosting migrates); refreshes, crashes and dropped connections return players to the same dig with their exact build; empty lobbies and server restarts can be resumed from checkpoints; solo digs can be continued after closing the game. Mid-run resume is therefore now part of the design. Co-op communication (chat, pings, callouts, spectating) and host lobby controls (remove, lock, password) are in scope.

## Scope and open decisions

Pass 11 (user request): controller support for play and menus, a basic Options menu (sound, display, sensitivity, invert, vibration, rebinding), and a Leave Dig option for every player. The user decided solo digs don't need mid-run saving because runs are short; online digs keep checkpoints only so players can rejoin.

This is a playable prototype with a complete run loop, not a finished game. Authored story, a surface hub, environmental puzzles, extensive vertical traversal and unique boss meshes are not implemented. Their exact designs have not been approved. Do not claim them as complete or invent requirements for them.

The next priorities should follow human playtesting: movement feel, camera visibility, target readability, useful drops, exploration density, guardian fairness and sound balance. Preserve the direction above when changing implementation. See docs/handoff/PLAYTEST-ROADMAP.md for a practical review order.

## Planned account progress, admin and Android support (2026-10-14)

The user wants account logins so permanent records, unlocks, Zenny and Workshop purchases follow the player across machines, a read-only owner dashboard for user/login/game statistics, and a native Android APK for Retroid Pocket 5 with browser/Windows cross-play, shared account progress and startup update checks. Preserve run-reset rules and Legends presentation on every platform. Collect limited operational/game metadata, not advertising analytics or device fingerprints.

These features are planned, not implemented. Confirmed choices: self-hosted Node + PostgreSQL + Better Auth on Ubuntu initially, email/password with open registration, online account run starts/purchases and retry after disconnect, separate offline guests, read-only admin powers and browser-download APK updates. Permanent progress remains separate from active-dig checkpoints; solo mid-run saving stays omitted. Co-op also gains a party-shared map, deferred cache choices and chest icons. Requirements, phase order and acceptance criteria are in [docs/handoff/ROADMAP.md](docs/handoff/ROADMAP.md).

## Repository and distribution intent

The user initially requested local-only work, then explicitly authorized committing this project and its handoff documents to https://github.com/Alialhashemi23/Megaman-Legends-Rogue. That authorization covers this repository. The user then requested browser play with online co-op on their own domain, published from their machines through a Cloudflare Tunnel; the project ships the server and deployment files, and the user runs the deployment. It still does not request public releases, monetization or uploading personal saves; keep the site non-commercial. Preserve attribution and the distinction between original project work and Capcom assets.
