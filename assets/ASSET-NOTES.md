# Local art provenance

The current Volnutt and Roll characters use the user-supplied original Mega Man Legends models, textures and skeletons from The Models Resource. The source pages credit Xinus23 as submitter; Capcom owns the game assets. They are excluded from the project's MIT grant. Full credits, modifications and source hashes are documented in `characters/CREDITS.md` and `tools/model-sources/conversion-report.json`. No original-game animation clips were supplied; all current movement clips were authored locally.

| Asset | Source | Use |
|---|---|---|
| `characters/volnutt.glb` | Supplied Megaman.dae and Megaman.png, The Models Resource / Xinus23 / Capcom | Playable Mega, original skin with new animation clips |
| `characters/roll.glb` | Supplied Roll_(Cutscene).dae and PNG, same archive credits | Playable Roll, original skin with new animation clips |
| Attached busters | `scripts/character.gd`, local geometry and paint | Animated weapon attachment and real muzzle position |
| Legacy Volnutt fan mesh and face SVG | `scripts/art.gd`, `volnutt_face.svg` | Earlier procedural source, no longer used for the player |
| `blue_armor.svg` | Authored SVG, 128 × 128 | Low-resolution blue panel painting |
| `ruin_wall.svg` | Authored SVG, 128 × 128 | Tileable masonry with seams, cracks, and edge highlights |
| `ruin_floor.svg` | Authored SVG, 128 × 128 | Large stone tiles with painted wear |
| `ruin_metal.svg` | Authored SVG, 128 × 128 | Vents, doorframes, and floor inserts |
| Robots and ruin modules | `scripts/art.gd` and `scripts/game.gd` | Original supporting geometry |
| Sound effects and ambience | `tools/audio/compose.py`, local waveform synthesis | 29 effects and ruin air loop |
| Original music | Original local MIDI compositions rendered with GeneralUser GS 2.0.3 by S. Christian Collins | Seven cues; credit and upstream license in `audio/` |

Mega Man Volnutt, Roll Caskett and Mega Man Legends belong to Capcom. The current playable meshes and textures are adapted game assets. The code license does not grant rights to those assets or character designs.

Sourcing options researched for future supporting assets:

- Kenney: https://kenney.nl/assets — CC0 assets, terms at https://kenney.nl/support.
- Poly Haven: https://polyhaven.com/ — CC0 source material, terms at https://polyhaven.com/license. Its realistic materials would need careful simplification to match this game's painted style.

Neither library was downloaded into this build. The project remains local and has not been uploaded to a repository or hosting service.

## UI pass

The following vector artwork was authored locally: `ui/parts_atlas.svg` (32 equipment/status icons), the historical `ui/mega_portrait.svg`, and `ui/menu_pattern.svg` (blue mechanical menu pattern). The current `ui/volnutt_portrait.png` and `ui/roll_portrait.png` are rendered directly from the supplied skinned game models and carry the same Capcom-asset exception as those models.

Two open-licensed fonts were downloaded from the official Google Fonts repository and bundled without modification:

- Russo One: https://github.com/google/fonts/tree/main/ofl/russoone — license at `fonts/RussoOne-LICENSE.txt`.
- Barlow Semi Condensed SemiBold: https://github.com/google/fonts/tree/main/ofl/barlowsemicondensed — license at `fonts/Barlow-LICENSE.txt`.

A menu reference image from https://pocketretrogamer.com/blog/why-mega-man-legends-on-playstation-1-is-a-unique-action-adventure-worth-playing was saved in `screenshots/ui-reference.png` for inspection only. It is not used as a game asset and is excluded from the playable content pack. No original game UI textures or fonts were extracted.
