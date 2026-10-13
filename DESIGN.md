# Mega Man Legends Rogue — design direction

Working game title: **Relic Diver — The Tidal Archive**. Repository name: Mega Man Legends Rogue. This is a non-profit fan project inspired by Mega Man Legends, with playable Mega Man Volnutt and Roll Caskett. It is not affiliated with Capcom. See LICENSE.md and asset credits for ownership.

## The experience we want

Explore a mysterious underground machine world as Mega. Turn a modest buster into an unusual build by finding parts that stack and interact. Search branching ruins, read robot attacks, survive a guardian, and decide whether to keep exploring before descending. The appeal is curiosity, readable action and growing combinations, grounded in the colorful PS1 adventure style of Legends.

The user's explicit choices are third-person free aim with optional lock-on; unlock new items and weapons between runs while power resets; colorful ancient machinery and mysterious robots; helmet-off Mega with brown hair and blue armor; low-poly models with painted textures. Roll is a second playable main character. Both currently share mechanics.

## Design pillars

1. **Legends atmosphere.** Warm painted stone, colorful mechanical accents, enclosed ruins, expressive silhouettes and friendly adventure energy. Mystery comes from the architecture and machines. Avoid replacing this with a dark military shooter or glossy modern realism.
2. **Dungeon exploration.** Branches, doors, cover, salvage and discoveries should make a chamber worth investigating. There is no time-based difficulty escalation. Descending increases difficulty; exploration can happen at the player's pace.
3. **Buster-first action.** Responsive movement, clear aim and lock-on, readable enemy preparation, and satisfying hit feedback. Movement animations should feel quick, compact and springy like Legends, with restrained sway and a firm firing arm.
4. **Parts that build on each other.** Risk of Rain is the reference for stackable themed drops and combinations. Parts should change decisions and create recognizable builds; it is not a request to copy that game's timer, exact items or presentation.
5. **Fresh runs, broader options.** Run statistics and fitted parts reset. Persistent progression expands the item and weapon pool rather than giving permanent starting damage or health.

## Current run loop

Select Mega or Roll and an unlocked buster → enter a seeded ruin → collect a starter part → explore connected chambers → fight machines and salvage scrap/XP → open caches and choose upgrades → defeat the guardian → explore further or use the lift → repeat across three descents → extract, or record the run on defeat.

Caches offer choices; healing wells create a competing use for scrap. Experience grants a paused upgrade choice. Parts stack, and combinations can trigger burn, chains, extra shots, splitting bolts, healing and defensive effects. Lifts preserve the current build and restore some Life. Details and current numbers are in README.md and scripts/game.gd; treat those as tunable prototype values.

## Combat and exploration direction

Keep free aim useful and optional lock-on dependable. Telegraph threats before damage: melee arcs, fixed aim lines, charge lanes, bombardment circles, shockwaves and beam lanes. Cover should consistently block attacks that visually hit it. Jumping and dashing need distinct practical uses.

Layouts should offer navigation choices and recognizable chamber functions, not only empty arenas joined by corridors. The current flat grid, five cover arrangements and three guardian variations establish the playable loop. Future vertical spaces, puzzles and more distinct guardians are possibilities, not already implemented features or settled requirements.

## Art and animation direction

Use the supplied original PS1 character geometry, texture atlases and rigs. Preserve helmet-off Mega's silhouette and Roll's identity. Nearest-filtered painted textures and simple lighting should remain readable. Avoid block-shaped replacement characters, excessive texture detail, gratuitous post-processing and modern material shine.

Original model archives contain no animation clips. The current clips are authored locally. Improve knee bends, foot placement, transitions and personality while preserving the original game's compact energy. Do not pursue exaggerated swagger, slow cinematic inertia or photorealistic motion capture. Aiming must remain steady and projectiles must originate at the animated muzzle.

## UI and audio direction

Menus use cobalt mechanical frames, cream lettering, a yellow selector, green Life segments, illustrated part icons and consistent spacing. Copy should feel like an adventure game: Life, Buster Parts, Dig, salvage and descents. Keep the combat center readable and descriptions useful for choosing builds.

Music should suggest an adventurous late-1990s console world through melodic electric piano, bells, marimba, guitar, bass and restrained percussion. The seven existing cues are original compositions. Ruin ambience and mechanical effects support space and feedback; attacks, pickups and menu actions need distinct sounds. Godot native audio currently handles these requirements.

## Scope and open decisions

This is a playable prototype with a complete run loop, not a finished game. Controller support, mid-run resume, authored story, a surface hub, environmental puzzles, extensive vertical traversal and unique boss meshes are not implemented. Their exact designs have not been approved. Do not claim them as complete or invent requirements for them.

The next priorities should follow human playtesting: movement feel, camera visibility, target readability, useful drops, exploration density, guardian fairness and sound balance. Preserve the direction above when changing implementation. See docs/handoff/PLAYTEST-ROADMAP.md for a practical review order.

## Repository and distribution intent

The user initially requested local-only work, then explicitly authorized committing this project and its handoff documents to https://github.com/Alialhashemi23/Megaman-Legends-Rogue. That authorization covers this repository. It does not request hosted gameplay, public releases, deployment, monetization or uploading personal saves. Preserve attribution and the distinction between original project work and Capcom assets.
