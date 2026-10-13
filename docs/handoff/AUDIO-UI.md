# Audio and UI handoff

## Sound direction and implementation

Use original melodic music and mechanical sounds that fit a late-1990s adventure. No original Mega Man music or game sound files were extracted. The current seven cues cover title, three descents, guardian, extraction and defeat. There are 29 effects plus ruin ambience.

Godot's native mixer provides Music, Effects, Menu and Ambience routing, a master limiter, light Effects reverb, capped voices, positional robot sounds and two-player music crossfades. Choices and pause lower the music; guardian activation switches cues. Volume preferences persist separately from run records. Runtime playback uses finished Ogg/WAV assets, so FluidSynth is unnecessary for players.

tools/audio/compose.py contains the original composition and sound synthesis; scores/*.mid are editable. GeneralUser-GS.sf2 and its upstream documentation/license are retained, as is the offline FluidSynth ZIP and license. To regenerate on Windows, extract fluidsynth.zip under tools/audio/fluidsynth/ so the directory expected by compose.py exists, install NumPy, and run the composer. See assets/audio/AUDIO-NOTES.md for paths, cue lengths, instrument rationale and credits. GeneralUser GS is a creative palette choice; do not claim it was Legends' original sound bank.

## Interface direction

Cobalt framed windows, cream shaded lettering, yellow selection cursor, green segmented Life gauge, mechanical background pattern, clear illustrated icons and consistent spacing. Fonts are bundled Russo One and Barlow Semi Condensed SemiBold with SIL OFL notices. Text uses Life, Buster Parts and Dig terminology. Preserve that language and readability rather than reverting to generic dark cards.

scripts/hud.gd drives title, HUD, pause, equipment, part choices, collection and results. UI scales uniformly within a widescreen safe area. Mouse, keyboard and controller navigation work through `nav_*` actions (arrows/D-pad/left stick, Enter/A, Esc/B), plus 1/2/3 upgrade shortcuts. Pass 11 replaced the Sound Settings page with Options (sound, display, controls) and a Controls & bindings page; key prompts come from `settings.prompt()` and follow the last device used. Character names and model-rendered portraits follow Mega/Roll selection. The equipment view reports actual weapon-adjusted power, fitted stack counts and combined effects.

Editable UI SVG sources and current portraits live in assets/ui/. The historical hand-drawn Mega portrait remains as source history but is not the current model portrait. tests/ui_checks.gd exercises interaction and resizing; tests/ui_preview.gd renders staged screens. tests/audio_checks.gd covers audio routing/settings/cues. Use test-only saves when previewing these systems.

## Video delivery

The user prefers videos playable in the conversation with sound. Current local full capture: build/preview/RelicDiver-motion-preview.mp4; short clip: motion-inline.mp4. Record using Godot --write-movie with --fixed-fps 30 and tests/record_video_preview.gd. Use FFmpeg to encode, and keep raw captures out of Git.

For inline playback, follow the visualize skill fully. A fragment with an embedded H.264/AAC MP4 under 1 MB was tested successfully at 640×400, 24 FPS and 19 seconds. build/preview/embed_motion.py and its literal HTML template reproduce it on the original PC. A new VP9 encoding failed browser playback despite valid file decoding; prefer the working MP4. Inline visualization storage and localhost servers are machine-specific and are not required to play the game.
