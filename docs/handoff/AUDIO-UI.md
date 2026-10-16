# Audio and UI handoff

## Polish P1 UI — shipped in build 23 (2026-10-15)

`scripts/hud.gd`:

- Workshop entry and character selection focus the first affordable node,
  falling back to the first unowned node, or the first node when all are fitted.
  Left/Right, stick horizontal and LB/RB switch diggers from anywhere on the
  page, and C/Y also works. Switching clears stale purchase messages. Focus
  resolves against the newly drawn buttons after mode changes.
- Title Credits moved from y=94 (overlapping Dig Record) to y=274. Start Dig
  keeps the default focus. Account text is width-limited.
- `title_account_copy()` words the account button/caption from the real auth
  state: Guest, checking, signing in, restoring/offline, signed in with sync
  status, or sign-in needed. It ignores profile requests from old generations.
  This is wording only; account persistence is unchanged.

Build 24 (owner report: controller treated headers and skills as one list):
`workshop_navigate()` gives the Workshop its own rows (headers / skills /
bottom buttons) instead of the flat `move_focus()` list. LB/RB call
`select_workshop_character()` directly. `workshop_label()` shows Locked,
Need N Z or Syncing. Headers are drawn with portraits and a clear selection.

Checks: `tests/progression_checks.gd` covers D-pad row navigation, Workshop entry focus, Right/LB
switching, unaffordable-tree fallback and stale vs current account checks.
UI/options/account checks pass. The title (with/without a saved dig, signed in
with a long name) and Workshop were rendered at 1440×900 and 960×600 with no
overlaps. Not covered: real controllers and Retroid, or a live browser
first-load session check.

## Latest music feedback — 2026-10-15

The user likes the current MIDI melodies and says they sound good, but estimates
the music is only about 50% of their desired quality and needs significant polish.
Preserve the melodies; improve arrangement, voicing, bass/percussion, phrasing,
instrument balance, dynamics, loops and mix while retaining the Legends-era
adventure sound. Update editable MIDI/composer sources and rendered runtime audio
together. See [POLISH-ROADMAP.md](POLISH-ROADMAP.md), phase P3, for the work plan.

## Pass 16 UI additions

Phase 4 adds the title Account panel and an `account` menu mode with native `nav_*` targets, Guest/cloud summaries, device codes, sync status/retry, takeover and migration confirmations, and safe local cleanup. Workshop/results show pending Zenny separately. Save-code imports cannot replace established cloud progress. See [ACCOUNT-SYNC.md](ACCOUNT-SYNC.md).

Workshop and Save Codes are menu modes with mouse, keyboard and controller navigation. Five prerequisite-gated purchases per digger; results lead to the Workshop, which returns to another solo dig or the online lobby. Import previews records/wallet and requires an explicit replacement action. Text fields must stay visible while on their page: hiding and re-showing them on every draw drops keyboard focus and breaks paste. Web progress also has a revisioned, checksummed localStorage recovery mirror for refreshes during IndexedDB sync. Options includes map_zoom, saved in settings.json.

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
