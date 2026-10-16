# Art and animation handoff

## Polish P2 ruins — shipped in build 23 (2026-10-15)

- `ruins.gd` gives each descent its own look: warm archive stone with blue
  ceramic pumps, green garden stone with copper fans, and pale indigo core
  stone with refractor regulators. Existing lamps get per-descent tints; no
  lights are added.
- Redrawn wall/floor/metal paintings, plus six new SVGs: machinery panels,
  ceramic borders, a floor seal and a 4×3 room-purpose crest atlas (ordering in
  `assets/textures/README.md`).
- `DiverArt.panels()` batches opaque QuadMeshes per material.
  `DiverArt.room_crest()` caches cropped atlas materials. Painted materials use
  nearest filtering, full roughness and zero specular.
- Details lie on existing wall and cover surfaces, with no new colliders or RNG
  draws. Protocol and checkpoint are unchanged.

Verified: clean SVG import. A dump of rooms, RNG state, every collision shape,
interactables and enemies for 4 seeds × 3 descents matches the previous commit
exactly; the only differing line is the player capsule's settle height, which
also varies between two runs of the baseline. Native draw calls dropped about
15% per descent (e.g. 1016 → 859 on B1), and frame time was the same or lower.
Contact-sheet renders of every room kind on all three descents show correct
panel/crest orientation and no z-fighting. The owner's visual approval and a
browser frame-time comparison are still pending.

## Polish P7 animation and movement — shipped in build 29 (2026-10-16)

Owner report: the dash had no visible animation. Causes: the 0.12 s blend into
a static, looping pose that lasted only for the 0.19 s dash (about 0.07 s at
full weight), a pose that actually leaned the torso back, and dash i-frames
blinking `art.root` on alternate frames.

- **Rig axes** (measured with a single-bone test render): the diggers face -Z;
  +X on Hips leans the torso back, +X on a leg swings it forward, +Z swings a
  hanging limb toward the digger's right (+X) and tips the upright torso to its
  left. Hips carries torso/arms/head; Pelvis carries the legs. Joint rest
  frames are pure translations.
- **Dash clips** (`DASH_KEYS` in the converter): onset (.10), travel (.24),
  glide (.50), plant (.66), settle, starting and ending on idle's first frame.
  `dash_left` mirrors `dash_right`. Servbot folds the pelvis into his legs and
  tilts more (`fold_servbot`). `character.gd` restarts the clip on the dash's
  rising edge with a 0.04 s blend, keeps it through the recovery, and blends
  out over 0.14 s. The plant at 0.24 s sounds a footstep. The aim layer keeps
  the buster steady through the lean.
- **Planted run/backpedal** (`PLANTED`, `planted()` in the converter):
  two-bone IK with forward knees onto a foot path. The stance sweep matches
  6.2 m/s (about 28% contact per foot), heel/toe roll (backpedal lands
  toe-first), a swing arc and an airborne moment. Body height dips mid-stance
  and is capped so planted boots reach. Torso and arms stay authored FK, and
  playback still scales with the digger's speed, so faster builds stay
  planted. Strafes and Servbot use the previous ground-fitted FK.
- **Landing:** a `land` squash after more than 0.3 s airborne when standing
  still; moving cancels it. **Cadence** scales with stick tilt (min 0.55).

Checks in `tests/character_checks.gd` cover dash selection/onset/recovery/aim,
remote dashes, landing, and planted boots (no sinking below the floor, no skating
while touching, steps alternating with airborne moments). Still open: strafes
skate (planting them sideways would cross the legs; a gallop/side-step design
is the likely route), and personality beyond the current per-digger tweaks
needs the owner's direction. Final balance is P8.

The user's direction is the original Mega Man Legends PS1 look, not a generic low-poly approximation. They specifically rejected the former blocky player model and later asked for movement to be less stiff while staying realistic to the original game.

## Source assets

Unmodified ZIPs and extracted COLLADA/OBJ/PNG sources: tools/model-sources/. Mega uses Megaman.dae; Roll uses the more detailed Roll_(Cutscene).dae. Roll_Caskett is retained as an alternative source. Both rigs have 18 joints and rigid skin weights, but no original clips. Preserve the source archives. Capcom ownership, Models Resource submitter Xinus23 and source links are documented in assets/characters/CREDITS.md.

tools/model-sources/build_characters.py converts the source skins to assets/characters/volnutt.glb and roll.glb. It preserves texture pixels, UVs and normalized weights, turns the characters to face -Z, scales them to 1.95 m and 1.88 m and puts their soles at the origin. The playable GLBs omit left-glove triangles so the fist does not intersect the attached cannon. Original archives retain that geometry. conversion-report.json records source hashes and conversion details.

## Animation pipeline

The converter authors twelve clips: idle, run, backpedal, left/right strafe, jump, fall, dash, hurt, fire, victory and defeat. These are original local clips inspired by Legends, not extracted original animation data. NumPy is required for conversion; tools/requirements.txt records it.

Import settings are significant: animation/remove_immutable_tracks=false prevents stale arm poses after releasing aim; skins/use_named_skins=true; meshes/generate_lods=false; animation/fps=60. Keep texture sampling nearest and the painted body material unshaded unless intentionally revising the art direction.

scripts/character.gd advances AnimationPlayer manually, then layers buster aim and recoil. The barrel attaches to LeftForeArm and the projectile origin is the actual muzzle marker. scripts/player.gd must not restart locomotion when shooting. Directional clip changes preserve gait phase, and footsteps use animation contact crossings.

Pass 07 uses distinct contact/push-off/recovery timing, modest torso counter-motion, knee bends, rolling boots and model-specific sole height fitting. Run length is .48 seconds; directional movement .56 seconds. Keep controls snappy. Avoid exaggerated sway or modern cinematic inertia. Further tuning should be judged in motion at the gameplay camera, not only in pose screenshots.

## Useful previews and checks

- tests/character_checks.gd: weights, binds, full-cycle boot contact, direction continuity, steady aim, aim release, both characters' projectiles and descent retention.
- tests/character_gallery.gd: six poses of both characters.
- tests/character_portraits.gd: portraits rendered from the actual models for assets/ui/.
- tests/character_game_preview.gd: staged title and gameplay views, plus Roll pause menu.
- tests/record_video_preview.gd: real renderer/mixer capture with scripted game input.
- tests/dash_preview.gd: side and back contact sheets of all four diggers for any clips (`-- <out dir> run,dash,...`).
- tests/record_dash_preview.gd: game-camera footage of every digger running, dashing in four directions and jumping (`--write-movie x.avi --fixed-fps 60`).

Environment art uses editable SVG textures in assets/textures/ plus modular geometry in art.gd and game.gd. The original PS1 geometry should remain the character reference; do not accidentally switch the player back to the historical procedural model still present in art.gd.
