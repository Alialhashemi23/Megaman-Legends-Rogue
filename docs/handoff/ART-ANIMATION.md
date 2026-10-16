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

## Planned polish P7 — animation and movement

The owner requested a dedicated phase and reports **the dash has no visible
animation**. Address that first. `character.gd` already selects a `dash` clip;
do not assume the asset is absent. Inspect authored poses, blending, dash state
duration/activation and aim-layer interaction, including remote co-op players.
Every digger needs a visible dash onset, travel pose and recovery, preserving
responsive controls and stable buster aim.

Then refine start/stop and directional transitions, planted feet, jump/landing
motion and personality with the supplied rigs and compact PS1 Legends energy.
P2 changes no animation code and does not fix the dash. See POLISH-ROADMAP.md;
final balance is now P8.

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

Environment art uses editable SVG textures in assets/textures/ plus modular geometry in art.gd and game.gd. The original PS1 geometry should remain the character reference; do not accidentally switch the player back to the historical procedural model still present in art.gd.
