"""Original Relic Diver score and sound design; run with the bundled Python.

GeneralUser GS is used only for offline instrument rendering. The game plays
the resulting Ogg/WAV files without FluidSynth or a SoundFont dependency.
"""
from pathlib import Path
import ctypes as C
import hashlib
import json
import math
import struct
import wave
import numpy as np
import os

ROOT = Path(__file__).resolve().parents[2]
WORK = Path(__file__).resolve().parent
OUT = ROOT / "assets" / "audio"
RATE = 32000
BIN = WORK / "fluidsynth/fluidsynth-v2.5.1-win10-x64-cpp11/bin"
os.add_dll_directory(str(BIN))
fluid = C.CDLL(str(BIN / "libfluidsynth-3.dll"))
snd = C.CDLL(str(BIN / "sndfile.dll"))

def api(name, result, args):
    fn = getattr(fluid, name)
    fn.restype, fn.argtypes = result, args
    return fn

ptr, integer = C.c_void_p, C.c_int
new_settings = api("new_fluid_settings", ptr, [])
setnum = api("fluid_settings_setnum", integer, [ptr, C.c_char_p, C.c_double])
setint = api("fluid_settings_setint", integer, [ptr, C.c_char_p, integer])
new_synth = api("new_fluid_synth", ptr, [ptr])
sfload = api("fluid_synth_sfload", integer, [ptr, C.c_char_p, integer])
program = api("fluid_synth_program_select", integer, [ptr, integer, integer, integer, integer])
cc = api("fluid_synth_cc", integer, [ptr, integer, integer, integer])
on = api("fluid_synth_noteon", integer, [ptr, integer, integer, integer])
off = api("fluid_synth_noteoff", integer, [ptr, integer, integer])
render = api("fluid_synth_write_float", integer, [ptr, integer, ptr, integer, integer, ptr, integer, integer])
delete_synth = api("delete_fluid_synth", None, [ptr])
delete_settings = api("delete_fluid_settings", None, [ptr])

class SFInfo(C.Structure):
    _fields_ = [("frames", C.c_longlong), ("samplerate", integer),
                ("channels", integer), ("format", integer),
                ("sections", integer), ("seekable", integer)]

snd.sf_open.restype = ptr
snd.sf_open.argtypes = [C.c_char_p, integer, C.POINTER(SFInfo)]
snd.sf_writef_float.restype = C.c_longlong
snd.sf_writef_float.argtypes = [ptr, ptr, C.c_longlong]
snd.sf_close.argtypes = [ptr]

def ogg(path, data):
    data = np.ascontiguousarray(data, dtype=np.float32)
    info = SFInfo(0, RATE, 2, 0x200000 | 0x0060, 0, 0)
    f = snd.sf_open(str(path).encode(), 0x20, C.byref(info))
    if not f:
        raise RuntimeError(f"Cannot write {path}")
    for start in range(0, len(data), 8192):
        block = data[start:start+8192]
        assert snd.sf_writef_float(f, block.ctypes.data, len(block)) == len(block)
    snd.sf_close(f)

def wav(path, data):
    data = np.asarray(data)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(2 if data.ndim == 2 else 1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((np.clip(data, -.98, .98) * 32767).astype("<i2").tobytes())

def varlen(n):
    result = [n & 127]
    while n >> 7:
        n >>= 7
        result.insert(0, 128 | (n & 127))
    return bytes(result)

def midi(path, score, bpm, beats, instruments, controls=()):
    # Editable type-0 MIDI, 480 ticks per quarter note.
    events = [(0, b"\xff\x51\x03" + int(60000000 / bpm).to_bytes(3, "big"))]
    for ch, preset in instruments.items():
        events += [(0, bytes([0xC0 | ch, preset])), (0, bytes([0xB0 | ch, 10, PANS.get(ch, 64)]))]
    for beat, ch, control, value in controls:
        events.append((round(beat * 480), bytes([0xB0 | ch, control, value])))
    for beat, duration, ch, note, vel in score:
        events += [(round(beat * 480), bytes([0x90 | ch, note, vel])),
                   (round((beat + duration) * 480), bytes([0x80 | ch, note, 0]))]
    events.sort(key=lambda x: (x[0], x[1][0] & 0xF0 != 0x80))
    buf, previous = bytearray(), 0
    for tick, msg in events:
        buf += varlen(tick - previous) + msg
        previous = tick
    buf += varlen(max(0, round(beats * 480) - previous)) + b"\xff\x2f\x00"
    path.write_bytes(b"MThd" + struct.pack(">IHHH", 6, 0, 1, 480) + b"MTrk" + struct.pack(">I", len(buf)) + buf)

PANS = {0: 49, 1: 64, 2: 79, 3: 88, 4: 39, 5: 30, 6: 98, 7: 72, 9: 64}
VOLUMES = {0: 82, 1: 92, 2: 90, 3: 55, 4: 52, 5: 62, 6: 70, 7: 50, 9: 75}
# Reverb sends: a wet lead and pads, a dry bass so the low end stays clear.
SENDS = {0: 38, 1: 8, 2: 62, 3: 80, 4: 70, 5: 56, 6: 66, 7: 60, 9: 30}

def render_score(name, title, bpm, bars, instruments, score, loop=True, controls=(), volumes=None, room=(.48, .17)):
    beats = bars * 4
    total = round(beats * 60 / bpm * RATE)
    settings = new_settings()
    setnum(settings, b"synth.sample-rate", RATE)
    setnum(settings, b"synth.gain", .48)
    setnum(settings, b"synth.reverb.room-size", room[0])
    setnum(settings, b"synth.reverb.level", room[1])
    setnum(settings, b"synth.chorus.level", .16)
    setint(settings, b"synth.cpu-cores", 1)
    synth = new_synth(settings)
    sfid = sfload(synth, str(WORK / "GeneralUser-GS.sf2").encode(), 1)
    assert sfid >= 0
    for ch, preset in instruments.items():
        assert program(synth, ch, sfid, 128 if ch == 9 else 0, preset) == 0
        cc(synth, ch, 10, PANS.get(ch, 64))
        cc(synth, ch, 7, {**VOLUMES, **(volumes or {})}.get(ch, 80))
        cc(synth, ch, 91, SENDS.get(ch, 40))
    events = []
    cycles = 2 if loop else 1
    # Kinds sort controllers first, then note-offs, then note-ons at one tick.
    for cycle in range(cycles):
        for beat, ch, control, value in controls:
            events.append((cycle * total + round(beat * 60 / bpm * RATE), 0, ch, control, value))
        for beat, duration, ch, note, vel in score:
            tick = cycle * total + round(beat * 60 / bpm * RATE)
            end = cycle * total + round((beat + duration) * 60 / bpm * RATE)
            events.extend([(tick, 2, ch, note, vel), (end, 1, ch, note, 0)])
    events.sort(key=lambda e: (e[0], e[1]))
    length = total * cycles + (0 if loop else RATE * 3)
    audio = np.zeros((length, 2), dtype=np.float32)
    position = 0
    for tick, kind, ch, a, b in events + [(length, 1, 0, 0, 0)]:
        tick = min(tick, length)
        if tick > position:
            section = audio[position:tick]
            assert render(synth, len(section), section.ctypes.data, 0, 2, section.ctypes.data, 1, 2) == 0
            position = tick
        if kind == 0: cc(synth, ch, a, b)
        elif kind == 2: on(synth, ch, a, b)
        else: off(synth, ch, a)
    delete_synth(synth)
    delete_settings(settings)
    if loop:
        # Render the first lap to establish reverb/release tails, keep the second.
        audio = audio[total:total * 2].copy()
        # Correct only the tiny DC/phase discontinuity in the last 4 ms.
        n = 128
        correction = audio[0] - audio[-1]
        audio[-n:] += np.linspace(0, 1, n, dtype=np.float32)[:, None] * correction
    else:
        audio[-RATE:] *= np.linspace(1, 0, RATE)[:, None]
    peak = float(np.max(np.abs(audio)))
    rms = float(np.sqrt(np.mean(audio ** 2)))
    # Match the previous loudness (so the in-game mix is unchanged) and round off
    # the few drum/crash peaks with a soft knee above .62 instead of turning
    # every quiet section down to make room for them.
    gain = min(1.05 / max(peak, 1e-8), .102 / max(rms, 1e-8))
    audio *= gain
    knee, room = .62, .2
    over = np.abs(audio) > knee
    audio[over] = np.sign(audio[over]) * (knee + room * np.tanh((np.abs(audio[over]) - knee) / room))
    ogg(OUT / "music" / f"{name}.ogg", audio)
    midi(WORK / "scores" / f"{name}.mid", score, bpm, beats, instruments, controls)
    manifest[name] = {"title": title, "bpm": bpm, "bars": bars, "seconds": round(len(audio) / RATE, 3),
                      "loop": loop, "peak": round(float(np.max(np.abs(audio))), 4),
                      "rms": round(float(np.sqrt(np.mean(audio ** 2))), 4), "notes": len(score)}
    print(f"Rendered {name}: {len(audio) / RATE:.1f}s, {len(score)} notes", flush=True)
    return audio

def note(score, beat, duration, ch, pitch, velocity):
    score.append((beat, duration, ch, int(pitch), max(1, min(127, int(velocity)))))

# Explicit original eight-bar phrases. Offset is in quarter notes; no borrowed
# melodies or game samples. Shared opening intervals tie the cues together.
MELODIES = {
    "title": [[(0, 1, 74), (1.5, .5, 76), (2, 1, 81), (3.5, .4, 78)],
              [(0, 1.4, 76), (2, .5, 74), (2.75, 1, 73)],
              [(.5, .75, 71), (1.5, .5, 74), (2.5, 1.25, 78)],
              [(0, 1, 76), (1.5, .5, 73), (2.5, 1.4, 69)],
              [(0, 1, 74), (1.5, .5, 78), (2, 1, 83), (3.25, .5, 81)],
              [(.5, 1, 78), (2, .5, 76), (2.75, 1, 74)],
              [(0, .5, 71), (1, .75, 73), (2, 1, 76)],
              [(0, .5, 73), (1, .5, 71), (2, 1.5, 69)]],
    "tidal": [[(.5, .5, 74), (1.5, .5, 77), (2.75, .75, 81)],
              [(0, 1, 79), (1.5, .5, 76), (3, .5, 74)],
              [(1, .5, 72), (2, .5, 74), (3, .75, 77)],
              [(.5, 1, 76), (2, 1.5, 72)],
              [(0, .5, 74), (.75, .5, 77), (2, .5, 81), (3, .5, 84)],
              [(.5, .75, 83), (2, .5, 79), (3, .75, 76)],
              [(0, .5, 77), (1, .5, 76), (2.5, .75, 74)],
              [(0, 1.4, 72), (2.5, 1, 69)]],
    "garden": [[(0, .5, 76), (1, .5, 79), (1.75, .75, 83), (3, .5, 81)],
               [(.5, .5, 79), (1.5, .75, 76), (3, .5, 74)],
               [(0, .75, 72), (1.5, .5, 76), (2.5, 1, 78)],
               [(.5, .5, 79), (1.5, .5, 76), (2.75, .75, 74)],
               [(0, .5, 76), (1, .5, 79), (2, .75, 86), (3, .5, 83)],
               [(.5, .75, 81), (2, .5, 79), (3, .5, 76)],
               [(0, .5, 78), (1, .5, 76), (2, .5, 74), (3, .5, 71)],
               [(.5, 1.25, 74), (2.5, 1, 72)]],
    "core": [[(0, .35, 69), (.75, .35, 72), (1.5, .6, 76), (3, .6, 74)],
             [(0, .5, 72), (1, .35, 71), (2.5, .75, 69)],
             [(.5, .5, 67), (1.5, .5, 71), (2.5, .75, 74)],
             [(0, .5, 72), (1.5, .5, 71), (3, .75, 68)],
             [(0, .5, 69), (1, .4, 72), (1.75, .5, 76), (2.5, .4, 79), (3.25, .5, 76)],
             [(.5, .6, 74), (1.5, .5, 72), (3, .5, 69)],
             [(0, .5, 71), (1, .5, 74), (2, .5, 77), (3, .5, 76)],
             [(0, 1, 71), (1.5, .5, 68), (2.5, 1, 64)]],
    "guardian": [[(0, .4, 74), (.75, .4, 77), (1.5, .4, 81), (2.5, .4, 80), (3.25, .4, 77)],
                 [(0, .75, 74), (1.25, .4, 72), (2, .4, 69), (3, .75, 70)],
                 [(0, .4, 77), (1, .4, 81), (2, .75, 84), (3, .4, 81)],
                 [(.5, .4, 80), (1.25, .4, 77), (2, .4, 74), (3, .75, 73)],
                 [(0, .4, 74), (.75, .4, 77), (1.5, .4, 81), (2.5, .75, 86)],
                 [(.5, .5, 84), (1.5, .5, 81), (2.5, .75, 77)],
                 [(0, .5, 79), (1, .5, 82), (2, .5, 81), (3, .5, 77)],
                 [(0, .5, 76), (.75, .5, 73), (2, 1.25, 69)]]
}

HARMONIES = {
    "title": [(38,[62,66,69,73]),(35,[62,66,69,73]),(31,[59,62,66,69]),(33,[61,64,67,71]),
              (38,[61,66,69,76]),(35,[62,66,69,74]),(31,[59,62,66,71]),(33,[61,64,67,71])],
    "tidal": [(38,[60,65,69,76]),(31,[59,62,65,69]),(36,[60,64,67,74]),(33,[60,64,67,71]),
              (38,[60,65,69,76]),(31,[59,62,65,69]),(34,[62,65,69,72]),(33,[60,64,67,71])],
    "garden": [(36,[60,64,67,71]),(33,[60,64,67,71]),(38,[60,64,66,69]),(31,[59,62,66,69]),
               (36,[60,64,67,74]),(33,[60,64,67,71]),(38,[60,64,66,69]),(31,[59,62,65,69])],
    "core": [(33,[57,60,64,67]),(29,[57,60,64,67]),(31,[55,59,62,65]),(28,[56,59,62,67]),
             (33,[57,60,64,67]),(29,[57,60,64,67]),(26,[57,62,65,69]),(28,[56,59,62,68])],
    "guardian": [(38,[62,65,69,72]),(34,[62,65,69,72]),(29,[60,65,69,72]),(33,[61,64,67,70]),
                 (38,[62,65,69,72]),(34,[62,65,69,72]),(31,[62,67,70,74]),(33,[61,64,67,70])]
}

# P3 arrangement pass. The melodies and chord changes above are the identity of
# each cue and are never altered here; this only decides who plays them, how the
# accompaniment moves under them and how each loop builds and breathes.
#
# Every looping cue runs through a form of eight-bar sections:
#   intro  - melody over held chords and a light groove
#   full   - the whole band; a second voice answers the melody in its rests
#   call   - melody split between lead (low) and answering voice, half-time feel
#   climax - harmony line, arpeggios, crashes, then a fill back to the top
STYLES = {
    "title": {"form": ["intro", "call", "climax"], "bass": "ballad", "comp": "arp", "drums": "brush",
              "extra": {5: 49, 6: 73, 7: 46}, "room": (.64, .22), "swing": 0,
              "volumes": {0: 74, 1: 86, 2: 96, 5: 66, 7: 60}},
    "tidal": {"form": ["intro", "full", "call", "climax"], "bass": "groove", "comp": "offbeat", "drums": "shuffle",
              "extra": {5: 71, 6: 79, 7: 46}, "room": (.58, .2), "swing": .05,
              "volumes": {0: 76, 1: 84, 2: 98, 6: 76, 7: 54}},
    "garden": {"form": ["intro", "full", "call", "climax"], "bass": "bounce", "comp": "strum", "drums": "bounce",
               "extra": {5: 75, 6: 71, 7: 13}, "room": (.46, .16), "swing": .03,
               "volumes": {0: 78, 1: 86, 2: 96, 7: 46}},
    "core": {"form": ["intro", "full", "call", "climax"], "bass": "drive", "comp": "pulse", "drums": "drive",
             "extra": {5: 62, 6: 80, 7: 98}, "room": (.42, .15), "swing": 0,
             "volumes": {0: 74, 1: 80, 2: 96, 5: 58, 7: 44, 9: 68}},
    "guardian": {"form": ["intro", "full", "call", "climax"], "bass": "battle", "comp": "power", "drums": "battle",
                 "extra": {5: 61, 6: 81, 7: 47}, "room": (.38, .13), "swing": 0,
                 "volumes": {0: 80, 1: 80, 2: 98, 5: 64, 6: 70, 7: 72, 9: 68}}
}
ENERGY = {"intro": .84, "full": 1.0, "call": .9, "climax": 1.08}
# Phrase arc: lean into the middle of each eight-bar phrase, ease off at its end.
ARC = [.93, .96, .99, 1.02, .96, 1.0, 1.04, .97]
PAD_EXPRESSION = {"intro": 92, "full": 106, "call": 98, "climax": 122}

def chord_tones(root, chord):
    return {p % 12 for p in chord} | {root % 12}

def voice_lead(chord, previous):
    # Same pitch classes, inverted to move as little as possible from the last chord.
    base = sorted(chord)
    options = []
    for shift in (-12, 0, 12):
        voicing = [p + shift for p in base]
        for _ in range(len(voicing)):
            options.append(sorted(voicing))
            voicing = voicing[1:] + [voicing[0] + 12]
    options = [o for o in options if o[0] >= 52 and o[-1] <= 81] or [base]
    if previous is None: return min(options, key=lambda o: abs(sum(o) - sum(base)))
    return min(options, key=lambda o: sum(abs(a - b) for a, b in zip(o, previous)))

def harmony_below(pitch, tones):
    # A third or sixth under the tune, always a chord tone.
    for gap in (3, 4, 8, 9, 5):
        if (pitch - gap) % 12 in tones: return pitch - gap
    return None

def approach(root, next_root, bar):
    # Lead the bass into the next chord: from a semitone below or a step above.
    if next_root == root: target = root + 7
    else: target = next_root - 1 if bar % 2 else next_root + 2
    return target + 12 if target < 26 else target

BASS = {
    "ballad": [(0, 1.4, 0, 1.0), (1.5, .45, 7, .8), (2, 1.4, 12, .9), (3.5, .45, None, .78)],
    "groove": [(0, .7, 0, 1.0), (.75, .2, 12, .6), (1.5, .45, 7, .82), (2.5, .6, 0, .9), (3, .4, 12, .75), (3.5, .4, None, .8)],
    "bounce": [(0, .4, 0, 1.0), (1, .4, 7, .8), (1.5, .35, 12, .74), (2, .4, 0, .92), (2.75, .3, 7, .7), (3, .4, 12, .8), (3.5, .4, None, .78)],
    "drive": [(i * .5, .38, [0, 0, 12, 0, 0, 12, 7, None][i], 1.0 if i in (0, 4) else .78) for i in range(8)],
    "battle": [(i * .5, .34, [0, 0, 12, 0, 0, 7, 12, None][i], 1.0 if i in (0, 3, 6) else .8) for i in range(8)] + [(3.75, .2, 12, .7)],
}

def arrange(name, bars):
    style = STYLES[name]
    rng = np.random.default_rng(sum(map(ord, name)) * 101)
    score, controls = [], []
    urgent = name in ["core", "guardian"]
    form = style["form"]
    per = bars // len(form)
    swing = style["swing"]
    voicing = None

    def add(beat, duration, ch, pitch, velocity, jitter=.008):
        if jitter: beat += float(rng.normal(0, jitter))
        note(score, max(0.0, beat), duration, ch, pitch, velocity + int(rng.integers(-3, 4)))

    def hit(beat, pitch, velocity, length=.1):
        # Drums: swing the off-beat eighths, keep the downbeats square.
        if abs(beat * 2 - round(beat * 2)) < 1e-6 and round(beat * 2) % 2: beat += swing
        add(at + beat, length, 9, pitch, velocity * energy, .006)

    for bar in range(bars):
        at = bar * 4
        index = min(bar // per, len(form) - 1)
        section = form[index]
        phrase = bar % 8
        root, chord = HARMONIES[name][phrase]
        next_root = HARMONIES[name][(bar + 1) % 8][0]
        tones = chord_tones(root, chord)
        energy = ENERGY[section] * ARC[phrase]
        melody = MELODIES[name][phrase]
        voicing = voice_lead(chord, voicing)
        if bar % per == 0:
            controls += [(at, 3, 11, PAD_EXPRESSION[section]), (at, 5, 11, 112 if section == "climax" else 96)]

        # --- Melody: unchanged notes, now with a partner voice ----------------
        lead_vel = (78 if urgent else 70) * energy
        if section == "call":
            # Call and response: lead takes the even bars low, the answer the odd bars.
            if bar % 2 == 0:
                for offset, duration, pitch in melody:
                    add(at + offset, duration, 2, pitch - (0 if name == "guardian" else 12), lead_vel, .004)
            else:
                for offset, duration, pitch in melody:
                    add(at + offset, duration * 1.05, 6, pitch, lead_vel * .92, .004)
        else:
            for offset, duration, pitch in melody:
                add(at + offset, duration, 2, pitch, lead_vel * (.9 if section == "intro" else 1), .004)
                if name in ["tidal", "garden"]:
                    add(at + offset + .5, min(.3, duration), 4, pitch, 27 * energy, 0)
                if section == "climax":
                    under = harmony_below(pitch, tones)
                    if under: add(at + offset + .01, duration * 1.1, 5, under, lead_vel * .72, .004)
            # In the full band, the second voice echoes the bar's opening motif.
            end = max(o + d for o, d, _ in melody)
            if section == "full" and bar % 2 == 1 and 4 - end >= 1.25:
                motif = [p for _, _, p in melody[:2]]
                lift = 12 if max(motif) <= 82 else 0
                for i, pitch in enumerate(motif):
                    add(at + end + .25 + i * .5, .42, 6, pitch + lift, 50 * energy, .004)

        # --- Chords -----------------------------------------------------------
        comp = style["comp"]
        held = section == "intro" or (section == "call" and comp != "power")
        if held:
            for i, pitch in enumerate(voicing):
                add(at + i * .015, 1.9 if section == "call" else 3.85, 0, pitch, (46 - i * 2) * energy)
            if section == "call":
                for i, pitch in enumerate(voicing): add(at + 2 + i * .015, 1.85, 0, pitch, (40 - i * 2) * energy)
        elif comp == "arp":
            for step, idx in enumerate([0, 2, 1, 3, 2, 1, 3, 2]):
                add(at + step * .5, .55, 0, voicing[idx % len(voicing)], (50 if step % 2 == 0 else 42) * energy)
        elif comp == "offbeat":
            for strike, dur, vel in [(0, .9, 52), (1.5, .4, 44), (2.5, .9, 48), (3.5, .4, 42)]:
                for i, pitch in enumerate(voicing): add(at + strike + i * .012, dur, 0, pitch, (vel - i * 2) * energy)
        elif comp == "strum":
            for strike, way, dur, vel in [(0, 1, .7, 56), (1, 1, .4, 46), (1.5, -1, .4, 40), (2.5, -1, .4, 42), (3, 1, .5, 50), (3.5, -1, .35, 38)]:
                strings = voicing if way > 0 else voicing[::-1]
                for i, pitch in enumerate(strings): add(at + strike + i * .018, dur, 0, pitch, (vel - i * 2) * energy)
        elif comp == "pulse":
            for step in range(8):
                accent = step in (0, 3, 6)
                for pitch in voicing[1:]: add(at + step * .5, .32, 0, pitch, (50 if accent else 34) * energy)
        elif comp == "power":
            chug = [root + 24, root + 31] if root + 31 <= 72 else [root + 12, root + 19]
            steps = range(0, 8, 2) if section == "call" else range(8)
            for step in steps:
                accent = step in (0, 3, 6)
                for pitch in chug: add(at + step * .5, .9 if accent and section == "intro" else .24, 0, pitch, (70 if accent else 54) * energy)

        # Pads hold through each pair of bars; climax adds an upper string line.
        if bar % 2 == 0:
            for pitch in voicing[:3]: add(at, 7.7, 3, pitch, 36 * energy, 0)

        # --- Colour voice (ch 7) --------------------------------------------------
        colour = style["extra"][7]
        if colour == 46 and section in ["full", "climax"] and (bar % 2 == 0 or section == "climax"):
            # Harp sweep up through the chord at the top of the bar.
            for i, pitch in enumerate(voicing + [p + 12 for p in voicing]):
                add(at + i * .25, .9, 7, pitch, (40 + i * 2) * energy)
        elif colour == 13 and section == "climax" and bar % 2 == 1:
            for i, pitch in enumerate(sorted(voicing)[-3:]): add(at + 3 + i * .25, .25, 7, pitch + 12, 46 * energy)
        elif colour == 98 and section in ["full", "climax"]:
            for step in range(16):
                add(at + step * .25, .2, 7, voicing[[0, 1, 2, 3, 2, 1, 2, 3][step % 8]] + 12, (34 if step % 4 == 0 else 24) * energy)
        elif colour == 47 and section != "call":
            drum = root + 12 if root + 12 <= 50 else root
            add(at, .8, 7, drum, (62 if section == "intro" else 76) * energy, .004)
            if phrase == 7:
                for i in range(8): add(at + 2 + i * .25, .25, 7, drum, (44 + i * 5) * energy, .003)

        # --- Bass ---------------------------------------------------------------
        lead_in = approach(root, next_root, bar)
        if section == "intro" and style["bass"] in ["ballad", "groove"]:
            add(at, 3.6, 1, root, 64 * energy)
            add(at + 3.5, .45, 1, lead_in, 50 * energy)
        elif section == "call":
            add(at, 1.85, 1, root, 70 * energy)
            add(at + 2, 1.4, 1, root + 7, 58 * energy)
            add(at + 3.5, .45, 1, lead_in, 54 * energy)
        else:
            for offset, dur, interval, weight in BASS[style["bass"]]:
                pitch = lead_in if interval is None else root + interval
                add(at + offset, dur, 1, pitch, (70 if urgent else 68) * weight * energy)

        # --- Drums ----------------------------------------------------------------
        kit = style["drums"]
        loop_end = bar == bars - 1
        fill_from = 2 if loop_end else 3 if phrase == 7 and not (kit == "brush" and section == "intro") else 4
        pattern = []
        if kit == "brush":
            if section == "call":
                pattern += [(0, 36, 48), (2.5, 36, 38), (1, 37, 44), (3, 37, 44)]
                pattern += [(b, 51, 38) for b in range(4)] + [(s * .5, 70, 32 if s % 2 else 24) for s in range(8)]
            elif section == "climax":
                pattern += [(0, 36, 60), (2, 36, 52)] + ([(2.5, 36, 44)] if bar % 2 else [])
                pattern += [(1, 38, 52), (3, 38, 54)] + [(s * .5, 51, 40 if s % 2 == 0 else 30) for s in range(8)]
        elif kit == "shuffle":
            pattern += [(s * .5, 42, 30 if s % 2 == 0 else 20) for s in range(8)]
            if section == "intro":
                pattern += [(0, 36, 52), (2.5, 36, 42), (3, 37, 40)]
            elif section == "call":
                pattern += [(0, 36, 58), (2, 37, 50), (.75, 64, 36), (2.25, 63, 34), (3.75, 64, 32)]
            else:
                pattern += [(0, 36, 66), (1.75, 36, 46), (2.5, 36, 54)]
                pattern += [(1, 38 if section == "climax" else 37, 56), (3, 38 if section == "climax" else 37, 58)]
                pattern += [(.75, 63, 40), (1.5, 64, 36), (2.25, 63, 38), (3.75, 64, 40)]
                if bar % 2: pattern.append((3.5, 46, 34))
                if section == "climax": pattern += [(b + .5, 54, 34) for b in range(4)]
        elif kit == "bounce":
            pattern += [(b, 75, 40) for b in (.75, 2.25, 3.75)]
            if section == "intro":
                pattern += [(0, 36, 56), (2, 36, 48)] + [(s * .5, 42, 26 if s % 2 == 0 else 16) for s in range(8)]
            elif section == "call":
                pattern += [(0, 36, 60), (2, 38, 52)] + [(s * .5, 42, 30 if s % 2 == 0 else 18) for s in range(8)]
            else:
                pattern += [(0, 36, 70), (1.5, 36, 52), (2, 36, 64)] + ([(3.5, 36, 48)] if bar % 2 else [])
                pattern += [(1, 38, 62), (3, 38, 64), (2.75, 38, 22)]
                pattern += [(s * .25, 42, [32, 14, 24, 14][s % 4]) for s in range(16)]
                if section == "climax": pattern += [(b + .5, 54, 36) for b in range(4)] + [(3.5, 46, 36)]
        elif kit == "drive":
            pattern += [(s * .5, 42, 34 if s % 2 == 0 else 22) for s in range(8)]
            if section == "intro":
                pattern += [(b, 36, 50) for b in range(4)]
            elif section == "call":
                pattern += [(0, 36, 64), (2.5, 36, 52), (2, 38, 58)] + [(s * .25 + .25, 42, 14) for s in range(0, 16, 2)]
            else:
                pattern += [(b, 36, 72) for b in range(4)] + [(1, 38, 66), (3, 38, 68), (1.5, 46, 32), (3.5, 46, 34)]
                if section == "climax" and phrase % 4 == 0: pattern.append((0, 49, 58))
        elif kit == "battle":
            if section == "intro":
                pattern += [(0, 36, 66), (.75, 36, 52), (2, 36, 60), (3, 38, 62)] + [(s * .5, 42, 30 if s % 2 == 0 else 20) for s in range(8)]
            elif section == "call":
                pattern += [(0, 36, 70), (1.5, 36, 56), (2, 38, 66)] + [(b, 51, 40) for b in range(4)]
            else:
                pattern += [(b, 36, 74 if b in (0, 2) else 60) for b in (0, .75, 1.5, 2, 2.75, 3.5)]
                pattern += [(1, 38, 72), (3, 38, 74)] + [(s * .5, 42, 40 if s % 2 == 0 else 28) for s in range(8)]
                if section == "climax" and phrase % 2 == 0: pattern.append((0, 49, 62))
                elif phrase == 0: pattern.append((0, 49, 58))
        for beat, pitch, velocity in pattern:
            if beat < fill_from or pitch in (75, 63, 64): hit(beat, pitch, velocity)
        if bar % per == 0 and index > 0 and kit != "brush" or (kit == "brush" and bar % per == 0 and section == "climax"):
            hit(0, 49, 60)
        if fill_from < 4:
            # Three alternating fills so phrase ends don't all sound the same.
            steps = int((4 - fill_from) * 4)
            variety = (bar // 8 + (1 if loop_end else 0)) % 3
            toms = [50, 48, 47, 45, 43, 41]
            for s in range(steps):
                beat = fill_from + s * .25
                if variety == 0: pitch = toms[min(s, 5)] if s < steps - 1 else 38
                elif variety == 1: pitch = 38
                else: pitch = 38 if s % 2 == 0 else toms[min(s // 2, 5)]
                hit(beat, pitch, (44 + s * (24 / steps)) * (1.1 if loop_end else 1), .08)
            hit(fill_from, 36, 60)

    # Clamp notes to the loop boundary for a valid editable loop file.
    clamped = [(b, min(d, bars * 4 - b - .01), c, n, v) for b, d, c, n, v in score if b < bars * 4 - .02]
    return clamped, controls

def check_melody(name, bars, score):
    # Every original melody note must be present (lead or answer, either octave).
    played = {(round(b * 4), n) for b, _, c, n, _ in score if c in (2, 6)}
    for bar in range(bars):
        for offset, _, pitch in MELODIES[name][bar % 8]:
            spot = round((bar * 4 + offset) * 4)
            assert any((spot + d, p) in played for d in (-1, 0, 1) for p in (pitch, pitch - 12)), (name, bar, offset, pitch)

def stinger(name, pitches, bpm):
    # Short end-of-dig cues: same tune, now with band, strings and a proper ending.
    score, controls = [], []
    last = len(pitches) - 1
    for i, pitch in enumerate(pitches):
        note(score, i * .5, .6 if i < last else 3, 2, pitch, 72 if i < last else 80)
    if name == "clear":
        for pitch in [62, 66, 69, 74]: note(score, 0, 3.4, 0, pitch, 52)
        for pitch in [62, 66, 69, 74, 78]: note(score, 3.5, 4, 3, pitch, 58)
        for i, pitch in enumerate(pitches):
            under = harmony_below(pitch, {2, 6, 9})
            if under: note(score, i * .5, .6 if i < last else 3, 5, under, 56 if i < last else 64)
        for at, dur, pitch in [(0, 1.8, 38), (2, 1.4, 45), (3.5, 4, 38)]: note(score, at, dur, 1, pitch, 76)
        for s in range(6): note(score, 2 + s * .25, .08, 9, 38, 40 + s * 7)
        for pitch, vel in [(36, 80), (49, 72), (57, 60)]: note(score, 3.5, .6, 9, pitch, vel)
        note(score, 0, .1, 9, 36, 66)
    else:
        for pitch in [50, 57, 60, 65]: note(score, 0, 6, 0, pitch, 46)
        for pitch in [50, 57, 62]: note(score, 0, 7, 3, pitch, 50)
        for at, dur, pitch in [(0, 2, 38), (2, 4.5, 38)]: note(score, at, dur, 1, pitch, 58)
        note(score, 2.5, 3, 5, 57, 44)
        for s in range(10): note(score, s * .2, .2, 7, 38, 20 + s * 2)
        note(score, 2.5, 1.5, 7, 38, 64)
    return score, controls

def sfx():
    rng = np.random.default_rng(314159)
    effects = {}
    def tone(duration, start, end, amp=.5, decay=7, noise=0, metallic=0):
        t = np.arange(round(duration * RATE)) / RATE
        phase = 2 * np.pi * (start * t + (end-start) * t*t / (2*duration))
        envelope = (1-np.exp(-t*1300)) * np.exp(-t / duration * decay)
        signal = np.sin(phase) + metallic * np.sin(phase * 2.71) + metallic*.5*np.sin(phase * 4.13)
        return amp * envelope * (signal + noise * rng.normal(size=len(t)))
    def mix(*layers):
        data = np.zeros(max(len(x) for x in layers))
        for x in layers: data[:len(x)] += x
        return np.tanh(data * 1.2) * .65
    def delay(signal, seconds): return np.pad(signal, (round(seconds * RATE), 0))
    def chime(pitches, spacing=.09, duration=.5):
        return mix(*(delay(tone(duration, 440*2**((p-69)/12),440*2**((p-69)/12),.29,5,0,.25), i*spacing) for i,p in enumerate(pitches)))
    for i in range(3):
        effects[f"shot_{i}"] = mix(tone(.15, 1400+i*60, 180,.43,8,.12),tone(.07,190,60,.35,6))
        effects[f"hit_{i}"] = mix(tone(.17,340+i*35,80,.45,9,.85,.45),tone(.09,170,110,.3,7))
        effects[f"step_{i}"] = tone(.10,150+i*20,65,.20,10,.65,.2)
    effects.update({
        "needle": mix(tone(.10,2100,340,.4,10,.12),tone(.05,260,90,.22,8)),
        "siege": mix(tone(.38,260,38,.66,7,.6),tone(.16,1100,90,.4,7,.25,.4)),
        "loot": chime([86,90,93],.065,.36),
        "scrap": chime([81,88],.045,.19),
        "health": chime([74,78,81],.08,.46),
        "hurt": mix(tone(.31,220,52,.44,5,.35,.4),tone(.20,650,170,.18,7)),
        "dash": tone(.24,540,120,.42,5,1.1),
        "jump": tone(.17,170,430,.27,5,.06),
        "land": tone(.19,105,43,.28,8,.5,.2),
        "level": chime([74,78,81,86,90],.1,.64),
        "enemy": mix(tone(.27,530,90,.39,7,.2,.6),tone(.12,160,65,.25,6)),
        "door": mix(tone(.75,100,65,.25,3,.3,.5),delay(tone(.25,220,120,.3,6,.4),.43)),
        "win": chime([74,78,81,86,90,93,98],.12,.7),
        "warning": mix(tone(.18,740,740,.24,2,0,.13),delay(tone(.18,622,622,.23,2),.21)),
        "slam": mix(tone(.70,100,26,.68,6,.95,.35),tone(.23,480,90,.3,6,.5,.3)),
        "destroy": mix(tone(.45,230,36,.45,6,.9,.65),delay(tone(.24,500,90,.2,6,.5),.10)),
        "guardian_down": mix(tone(1.2,160,26,.55,4,.7,.55),delay(chime([62,69,74,81],.12,.65),.33)),
        "menu_move": tone(.055,950,820,.16,6,0,.10),
        "menu_confirm": chime([81,86],.055,.18),
        "lock": chime([86,93],.065,.14)
    })
    for name, data in effects.items():
        data[-min(160,len(data)):] *= np.linspace(1,0,min(160,len(data)))
        wav(OUT / "sfx" / f"{name}.wav", data)
    # Quiet, periodic ventilation, resonant pipes and distant motors.
    n = RATE * 24
    t = np.arange(n) / RATE
    result = []
    for ch in range(2):
        noise = rng.normal(size=n)
        spectrum = np.fft.rfft(noise)
        frequencies = np.fft.rfftfreq(n, 1 / RATE)
        spectrum *= np.exp(-frequencies/750) * (1-np.exp(-frequencies/70))
        air = np.fft.irfft(spectrum, n=n)
        motor = np.sin(2*np.pi*55*t + .2*np.sin(2*np.pi*t/12)) * .018
        pipe = np.sin(2*np.pi*(165+ch*.125)*t) * (.004+.003*np.sin(2*np.pi*t/8))
        result.append(air*.055 + motor + pipe)
    ogg(OUT / "ambience" / "ruin_air.ogg", np.stack(result, axis=1))
    return len(effects)

if __name__ == "__main__":
    for folder in [OUT/"music", OUT/"sfx", OUT/"ambience", WORK/"scores"]: folder.mkdir(parents=True, exist_ok=True)
    manifest = {}
    specs = [
        ("title","Beyond the Breakwater",96,24,{0:4,1:33,2:11,3:89,9:0}),
        ("tidal","Footsteps in the Tidal Archive",104,32,{0:4,1:33,2:10,3:89,4:73,9:0}),
        ("garden","Engines in Bloom",112,32,{0:27,1:33,2:12,3:48,4:11,9:0}),
        ("core","Below the Sun",124,32,{0:5,1:38,2:81,3:89,9:8}),
        ("guardian","Keepers of the Old World",138,32,{0:30,1:38,2:80,3:48,9:8})]
    previews = []
    for name,title,bpm,bars,instruments in specs:
        style = STYLES[name]
        score, controls = arrange(name, bars)
        check_melody(name, bars, score)
        audio = render_score(name,title,bpm,bars,{**instruments,**style["extra"]},score,True,controls,style["volumes"],style["room"])
        preview = audio[RATE*8:RATE*20].copy()
        preview[:RATE] *= np.linspace(0,1,RATE)[:,None]
        preview[-RATE:] *= np.linspace(1,0,RATE)[:,None]
        previews.extend([preview,np.zeros((RATE,2),dtype=np.float32)])
    for name,title,pitches,bpm,instruments in [("clear","Back to the Surface",[74,78,81,86,85,81,78,86],112,{0:4,1:33,2:11,3:48,5:61,9:0}),
                                               ("lost","A Light Left Below",[74,72,69,65,64,62],80,{0:4,1:33,2:11,3:49,5:71,7:47})]:
        score, controls = stinger(name, pitches, bpm)
        render_score(name,title,bpm,2,instruments,score,False,controls,{5:58} if name=="clear" else {7:70},(.6,.22))
    count=sfx()
    ogg(WORK/"soundtrack-preview.ogg",np.concatenate(previews))
    (WORK/"score-manifest.json").write_text(json.dumps({"soundfont_sha256":hashlib.sha256((WORK/"GeneralUser-GS.sf2").read_bytes()).hexdigest(),"tracks":manifest,"sound_effects":count},indent=2))
    print(f"Complete: {len(manifest)} music cues, {count} effects, ambience, and preview.",flush=True)
