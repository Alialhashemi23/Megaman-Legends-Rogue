# Presentation and progression planning — 2026-10-15

Status: core product choices settled; implementation brief below. No gameplay
changes implemented in this planning pass.
Read alongside DESIGN.md and NEXT-FEATURES.md. This records the user's latest
priorities without replacing previously accepted co-op or account/Android work.

**Baseline correction:** the hosting checkout on `D:` is newer than the workspace
initially reviewed here. Accounts/admin and co-op map/deferred reward work have
already landed there. [POLISH-ROADMAP.md](POLISH-ROADMAP.md) defines the reconciled
phase order and newly authorized push/deployment workflow; use it over older
pending-status and owner-only-deployment statements below.

## Confirmed direction

- Presentation and progression are the user's biggest current concerns.
- Music is also a significant polish priority: the user likes the current MIDI
  melodies and sound, but rates the result at roughly 50% of their desired
  quality. Preserve melodic identity while improving arrangement, phrasing,
  instruments, dynamics, loops and mixing in the original console style.
- Prioritize ruins and atmosphere for the first presentation pass. Fidelity to
  the original Mega Man Legends PS1 look is the most important visual constraint.
  The user explicitly warns that a modern appearance takes away from the vibe.
  Preserve supplied character assets, painted textures, simple geometry,
  colorful ancient machinery, and restrained lighting. More detail must support
  that established style, not introduce glossy realism or excessive effects.
- In-run progression should combine frequent stackable upgrades with occasional
  build milestones: parts that noticeably change attacks and create synergies.
- Guardian rewards are the selected source of major upgrades: each guardian
  offers a major choice influenced by the player's currently fitted parts.
- Between-run progression should add branching character specializations with
  one specialization equipped per dig, alongside existing modest permanent
  bonuses. Purchased specializations can be switched freely between digs.
  Preserve purchased nodes, earned progress, and run power resets.
- The Workshop must be a Final Fantasy X-esque skill tree / Sphere Grid. This is
  an explicit user requirement, not just a suggestion for menu decoration.
  Design connected, navigable progression with meaningful routes and junctions;
  a flat purchase list or simple specialization selector alone is insufficient.
  Present it in the established Legends cobalt mechanical interface.
- Each character has their own grid. Spend Zenny to activate nodes connected to
  purchased paths; no separate movement currency or activation spheres.
- Every node on a character's grid must eventually be obtainable through play.
  Branching determines purchase order, not permanent exclusion. Owning the full
  grid unlocks every specialization option, while one remains equipped per dig.
- Solo and co-op should receive equal consideration. New specializations must
  be useful alone as well as with friends.
- The user additionally requested a dedicated animation/movement phase and
  specifically reports that dash has no visible animation. P7 addresses that
  first, then transitions, foot placement and personality, retaining responsive
  controls and steady aiming. Final balance moves to P8.
- The user is interested in all five longer-term proposals: secrets/room events,
  distinct enemies/bosses, more expressive builds, character abilities, and a
  small surface hub. These are broad interests, not finalized feature designs
  or an instruction to implement all five in one pass.

## Tuning still open

Unlock pacing remains undecided. The user prioritizes Sphere Grid structure and
eventual completion through continued character play, rather than a particular
number of runs. Do not record the suggested 1–2-dig first specialization as
approved. Keep the existing shared personal Zenny wallet unless later changed;
the latest answer does not explicitly request character-specific currencies.

Exact branch abilities, item effects, prices, and art assets are not approved yet.
Questionnaire recommendations are proposals until the user selects them.

## Proposed implementation structure

The grid records permanent development and unlocked options. A separate pre-dig
selection equips exactly one unlocked specialization; run drops then develop
that playstyle. Label permanent passive effects and equipped-only effects
explicitly so reaching several branches does not silently activate every
specialization at once. The grid must allow eventual completion without mutually
exclusive purchases. Before a player unlocks a specialization, preserve their
existing signature attack and abilities as the default loadout.

Guardian milestone choices should be personal in co-op and derive from each
player's own parts. Implementations need useful fallback choices for sparse
builds, clear effect descriptions, and checkpoint/rejoin preservation. Resolve
the usefulness of the final guardian's reward within the three-descent loop;
do not quietly turn a run upgrade into permanent power.

## First implementation brief

Build in reviewable stages. The stage order below is a recommendation, not a
claim that the user approved exact content, costs, or effects.

### 1. Establish the ruins art treatment

Start with one representative chamber and its adjoining passage, using the
existing geometry/texture pipeline. Add painted machinery panels, recognizable
door frames, purposeful equipment clusters, and a large navigation landmark.
Use these pieces to distinguish chamber functions and subsequently extend the
treatment across the three descents. Retain their existing names and themes.

Judge the result at the normal gameplay camera with the supplied characters in
frame. Textures, scale, silhouettes, and colors must feel consistent with those
characters. Preserve simple materials and restrained lighting; avoid realistic
reflections, cinematic blur, or effects that conceal the painted artwork.

Acceptance: the room is recognizable from multiple entrances; exits, enemies,
attack warnings, and pickups remain legible; decoration does not obstruct paths,
camera, or shots unexpectedly. Check representative browser performance before
expanding prop density. Render comparable before/after views for visual review.

### 2. Replace the Workshop list with four connected grids

Provide pan/zoom, recenter, readable links, distinct owned/available/locked node
states, a focused-node description/cost panel, and controller navigation that
keeps the selected node visible. Show prerequisites and completion progress.
Use cobalt mechanical framing, cream text, yellow focus, and painted icons.

Map existing purchases into the new layout without charging again or changing
their earned effects. Ensure every node can be reached and purchased on one
profile. Side branches and reconnecting paths should create route choices;
unnecessary filler stat nodes should not inflate the grid.

Start with two specialization destinations per character as a proposed first
content scope. Candidate themes for design, not approved mechanics:

| Character | Candidate branch A | Candidate branch B |
|---|---|---|
| Mega | Focused, precise buster fire | Repeated shots and ricochet effects |
| Roll | Self-repair and nearby ally support | Sustained needle fire and weak-point pressure |
| Tron | Concentrated siege damage | Area control and wider blasts |
| Servbot | Focused demolition | Mobile bombing and salvage utility |

Support choices must retain solo value. Large summoned-helper systems remain
future content unless explicitly included in a later implementation scope.
Clearly separate permanently active modest bonuses from equipped specialization
effects. Budget cumulative passive power for a fully completed grid; completion
must not undermine the importance of the run's parts and guardian upgrades.

Acceptance: old profiles and save codes preserve all earned progress; every grid
can reach 100% completion; only the selected specialization affects a dig; swaps
are free between digs and cannot alter an active/rejoined build. Purchases remain
atomic. Keyboard, mouse, and controller flows work at existing supported sizes.

### 3. Add guardian build milestones

Offer major personal rewards influenced by fitted parts, with readable before/
after descriptions and useful alternatives for builds without matching parts.
Candidate effects include chaining a Pulse impact, changing burn behavior, or
altering bomb patterns; exact effects and weights are implementation proposals.
Make effects visible using compact PS1-style sprites and simple shapes while
preserving steady aim and readable enemy warnings.

Acceptance: regular parts still stack; milestone effects change actual play;
choices reflect each player's build in co-op; duplicate packets/rejoins cannot
grant a reward twice; new runs clear milestone effects. Integrate selection with
the already-requested deferred co-op reward flow. Resolve the last guardian's
reward timing/usefulness before implementing that portion of the run loop.

### Verification and shipping

Use isolated profiles for migration, grid reachability, purchase validation,
specialization effects, reward selection, reset, and co-op restoration checks.
Read the relevant technical/UI/network handoffs before changing those systems.
Update protocol/checkpoint versions only as required by compatibility changes.
The hosting checkout already has authoritative account purchase validation;
update server grid rules, account migrations and client rules together.
Review actual renders and exercise browser/controller flows; automated checks
do not establish visual fidelity or balance. After gameplay changes, refresh
the Windows content pack, portable ZIP, web ZIP, and notices. Push/deploy completed
phases as explicitly authorized in POLISH-ROADMAP.md.

## Review evidence and implementation implications

Reviewed HANDOFF.md, DESIGN.md, NEXT-FEATURES.md, FEATURE-REPORT.md,
PLAYTEST-ROADMAP.md, ART-ANIMATION.md, relevant sections of ruins.gd and enemy.gd,
the item table in game.gd, progression.gd, and saved gameplay/room/Workshop renders.
No fresh hands-on playtest was performed. Historical screenshots support visual
discussion; they do not establish current movement feel or balance.

The current pool has 13 parts. The Workshop has five nodes per character, mostly
shared bonuses with signature research/modifiers. Extending specialization data
will require deliberate profile/save-code migration and co-op/checkpoint handling;
do not silently discard old purchases or reset personal saves.

The initial review treated shared map discovery/clears, deferred choices, chest
icons and account/admin/Android as pending. The later hosting-checkout review
found these implemented there, with Android hardware verification still pending.
Use that checkout's current handoffs and POLISH-ROADMAP.md rather than repeating
the old work. Account implementation choices need not be reopened.

This planning-only pass requires no export, deployment, or gameplay test rerun.
