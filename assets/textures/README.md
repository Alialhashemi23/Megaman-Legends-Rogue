# Painted ruins textures

Original project artwork, kept as editable SVGs and rasterized by Godot at the
declared small dimensions. These are not extracted Mega Man textures. Preserve
nearest sampling, matte materials and the painted late-1990s appearance.

P2 replaces the three shared stone/floor/metal paintings and adds:

- `ruin_archive_panel.svg`: tide gauge and ceramic pump manifold, 128 × 128.
- `ruin_garden_panel.svg`: copper fan and edge vegetation, 128 × 128.
- `ruin_core_panel.svg`: sealed refractor regulator, 128 × 128.
- `ruin_border.svg`: worn geometric ceramic band, 128 × 32.
- `ruin_floor_seal.svg`: muted floor inlay, 128 × 128.
- `ruin_crests.svg`: twelve 96 × 96 room-purpose motifs, four columns and three
  rows. In reading order: landing, pillars, relay, storage, coolant, foundry,
  vault, terrace, concourse, guardian, junction, dead-end salvage.

`DiverArt.room_crest()` crops the atlas; `DiverArt.panels()` batches faces by
material. `DiverRuins` places them on existing wall/fixture surfaces. Emblems are
environmental signs, not new interactables or rewards. Existing cover and floor
colliders are retained; no gameplay random draws are added.

Source-only as of 2026-10-15. The owner requested no engine launch or testing
while gaming. New SVG imports, atlas orientation, visual quality, z-fighting,
lighting, distance shimmer and browser performance still need review before
packaging/shipping. Do not treat the SVGs as approved in-game screenshots.
