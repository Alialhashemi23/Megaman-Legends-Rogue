# Character models and rig integration

The original Mega Man Volnutt and Roll Caskett meshes, texture atlases and
skeletons are Capcom game assets from Mega Man Legends (PlayStation).
The user supplied the downloaded archives from The Models Resource. Both pages
credit Xinus23 as the submitter, dated March 21, 2020:

- Mega Man Volnutt: https://models.spriters-resource.com/playstation/megamanlegends/asset/317687/
- Roll Caskett: https://models.spriters-resource.com/playstation/megamanlegends/asset/317688/

The source archives are retained unchanged in `tools/model-sources/volnutt.zip`
and `roll.zip`, with extracted COLLADA, OBJ and PNG sources alongside them.
Roll's more detailed `Roll_(Cutscene)` model is used. Her overworld model is
preserved as an alternative source. The archives contain skin weights and rigs,
but no animation clips or separate reuse license. Their availability on an
archive site does not make the Capcom assets part of this project's MIT license.

## Tron Bonne and Servbot (added later)

The Tron Bonne and Servbot meshes, textures and skeletons are likewise Capcom
game assets from Mega Man Legends (PlayStation). The user supplied both
archives, named "PlayStation - Mega Man Legends - Non-Playable Characters -
Tron Bonne" and "... - Servbot" in the style of The Models Resource; their
page links and submitter were not recorded. The archives are retained unchanged
in `tools/model-sources/tron.zip` and `servbot.zip`, with the extracted files
alongside. Tron's `Tron_Bonne_(Cutscene)` model is used (17 joints: the same
rig as Mega and Roll with one fewer face joint). The Servbot has 7 joints, one
per limb. The same terms apply: no animation clips, no reuse license, and not
part of this project's MIT license.

The converter gives both the same twelve locally authored clips. Tron's left
hand is replaced by the attached buster like the others. The Servbot has no
hand geometry to remove; its smaller buster sits on its single arm joint, its
whole arm aims, and its run adds a side-to-side waddle. The Servbot stands
1.08 m tall and Tron 1.86 m. All four diggers share the same mechanics for now.

## Local adaptation

`tools/model-sources/build_characters.py` converts the supplied COLLADA skins to
standard glTF 2.0, packed into `volnutt.glb` and `roll.glb`. It preserves the
original texture pixels, UV mapping and rigid PS1 skin weights, converts the
coordinate system to face Godot's -Z direction, scales the characters to 1.95 m
and 1.88 m, and places the soles at the character origin. Both rigs retain all
18 original joints, renamed to readable limb names. Original files are not
modified. Source and texture SHA-256 hashes are in `conversion-report.json`.

The left glove triangles are omitted in the playable GLB variants so that fists
do not protrude through the attached buster barrels. Everything else retains
the original geometry. An original local cannon attaches to the left forearm;
Roll receives a red version of the same tool. The runtime muzzle follows the
actual posed bone. Weapon core color follows Pulse, Needle or Siege selection.
The original unmodified glove geometry remains in the supplied source archives.

Twelve new skeletal clips were authored locally for both rigs: idle, run,
backpedal, left/right strafe, jump, fall, dash, hurt, fire, victory and defeat.
They are embedded in each GLB and editable through Godot's imported animations.
These are new animation poses, not extracted original-game animations.
Locomotion has no root motion; the existing CharacterBody3D controls collision,
jumps and dash distance. `scripts/character.gd` advances clips manually, blends
transitions, then layers buster aim and recoil over the arm without restarting
the running clip. Disabling immutable-track removal on import keeps releasing
aim from leaving a stale bone rotation.

The motion refinement replaces mirrored leg swings with compact contact,
push-off and recovery poses, subtle torso counter-motion and rolling boots.
Body height is fitted to each model's skinned boot soles. Direction changes
retain stride phase, footstep sounds follow animation contacts, and the aiming
layer compensates for torso rotation. The goal is the original Legends feel;
these remain newly authored clips rather than recovered original animations.

## Integration

The title screen offers Mega and Roll; press C to switch or use the mouse and
menu navigation. Both use the same combat statistics, buster options, loot,
unlock pool and run progression. Character selection carries through descents.
The current character's name and a portrait rendered directly from the imported
mesh appear in the HUD and pause menu. `tests/character_portraits.gd` regenerates
the portraits; `character_gallery.gd` renders a six-pose gallery.

`tests/character_checks.gd` checks selection, original binds, normalized weights,
animation poses, aim direction, firing while running, returning to a relaxed
arm, projectile hits for both characters, and character retention on descent.
The procedural-model build is recoverable in `backups/v5/`; the first imported
character pass is preserved in `backups/v6/`.

All project changes, source assets, generated files and playable builds remain
local. No repository or publishing action was performed.
