# Relic Diver audio

The music is newly composed for this local prototype. No Mega Man songs, MIDI
transcriptions, extracted game sound banks, or game sound effects are used.

## Engine decision

Playback uses Godot's native audio engine. Music, Effects, Ambience and Menu
buses feed Master; a master limiter catches peaks, and the Effects bus adds a
small room reverb. Two music players crossfade over approximately 1.2 seconds.
Enemy effects use 3D distance and stereo positioning, while player feedback,
attack warnings and menus remain clearly audible. Voices and repeated events
are capped. Audio variation uses its own random generator, independent of loot
and dungeon generation.

FMOD and Wwise would add a separate authoring application, integration and
runtime dependency. Godot covers this game's current needs: streamed music,
crossfades, positional effects, buses and volume controls. FluidSynth is an
offline instrument renderer only; it is not loaded by the game.

## Instrument source

GeneralUser GS 2.0.3, by S. Christian Collins, provides the sampled instruments.
Its restrained General MIDI palette fits the intended late-1990s adventure
sound: electric piano, vibraphone, marimba, clean guitar, bass, soft pads and
acoustic/electronic percussion. This is a creative choice, not a claim that
Legends used this bank. Its license explicitly permits private and commercial
music creation; the complete upstream terms and sample-origin notes are saved
unchanged in `GeneralUser-LICENSE.txt`.

- Author: https://schristiancollins.com/generaluser.php
- Author's source: https://github.com/mrbumpy409/GeneralUser-GS
- Offline renderer: https://github.com/FluidSynth/fluidsynth/releases/tag/v2.5.1
- Godot audio: https://docs.godotengine.org/en/stable/tutorials/audio/audio_buses.html

The unmodified SoundFont, renderer, documentation, composition source, editable
MIDI scores, and SHA-256 manifest are kept in `tools/audio/`, excluded from the
playable content pack. Existing online sound libraries were unnecessary for
this pass: all effects and ambience were synthesized locally with deterministic
noise, pitch envelopes, inharmonic resonances and layered transients.

## Cues

| File | Title | Use | Length |
|---|---|---|---|
| `music/title.ogg` | Beyond the Breakwater | Title / collection | 60.0 s |
| `music/tidal.ogg` | Footsteps in the Tidal Archive | Descent 1 | 73.8 s |
| `music/garden.ogg` | Engines in Bloom | Descent 2 | 68.6 s |
| `music/core.ogg` | Below the Sun | Descent 3 | 61.9 s |
| `music/guardian.ogg` | Keepers of the Old World | Active guardian in the current room | 55.7 s |
| `music/clear.ogg` | Back to the Surface | Successful extraction, once | 7.3 s |
| `music/lost.ogg` | A Light Left Below | Defeat, once | 9.0 s |

The five main cues loop. They are rendered through a warm-up lap to retain
release/reverb tails at the loop boundary. Pausing, inspecting parts and choosing
upgrades retain the current cue and lower its level. Defeating or leaving a
guardian restores that descent's track. Music is 32 kHz stereo Ogg Vorbis;
short effects are mono 16-bit WAV. There are 29 effect files, including three
variations each for the pulse buster, impacts and footsteps, and a quiet stereo
ruin ambience loop. The music and effects occupy about 4.9 MB before packaging.

## Editing and playback

`tools/audio/compose.py` contains the note phrases, harmonies, arrangement,
instrument choices, MIDI writer, offline rendering and effect synthesis. Run it
with the bundled Python to regenerate the audio. `tools/audio/scores/*.mid` can
also be edited in a MIDI sequencer. `tools/audio/soundtrack-preview.ogg` is a
65-second medley of the five main themes; `in-game-mix.wav` is a captured runtime
mix used to check playback and clipping.

Pause → Sound Settings controls Master, Music, Effects (including menus), and
Ambience. Up/down selects a row; left/right changes it by 5%; Enter or a click
raises it by 10%, wrapping from 100% to Off. M toggles mute globally. Levels are
saved in `save/audio.json`, separately from run records. The source and portable
build each retain their own local settings. There are no network calls in the
game's audio system.
