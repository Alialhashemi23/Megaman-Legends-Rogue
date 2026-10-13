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

def midi(path, score, bpm, beats, instruments):
    # Editable type-0 MIDI, 480 ticks per quarter note.
    events = [(0, b"\xff\x51\x03" + int(60000000 / bpm).to_bytes(3, "big"))]
    for ch, preset in instruments.items():
        events += [(0, bytes([0xC0 | ch, preset])), (0, bytes([0xB0 | ch, 10, PANS.get(ch, 64)]))]
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

PANS = {0: 49, 1: 64, 2: 79, 3: 88, 4: 39, 9: 64}

def render_score(name, title, bpm, bars, instruments, score, loop=True):
    beats = bars * 4
    total = round(beats * 60 / bpm * RATE)
    settings = new_settings()
    setnum(settings, b"synth.sample-rate", RATE)
    setnum(settings, b"synth.gain", .48)
    setnum(settings, b"synth.reverb.room-size", .48)
    setnum(settings, b"synth.reverb.level", .17)
    setnum(settings, b"synth.chorus.level", .16)
    setint(settings, b"synth.cpu-cores", 1)
    synth = new_synth(settings)
    sfid = sfload(synth, str(WORK / "GeneralUser-GS.sf2").encode(), 1)
    assert sfid >= 0
    for ch, preset in instruments.items():
        assert program(synth, ch, sfid, 128 if ch == 9 else 0, preset) == 0
        cc(synth, ch, 10, PANS.get(ch, 64))
        cc(synth, ch, 7, {0: 82, 1: 92, 2: 90, 3: 55, 4: 52, 9: 75}.get(ch, 80))
    events = []
    cycles = 2 if loop else 1
    for cycle in range(cycles):
        for beat, duration, ch, note, vel in score:
            tick = cycle * total + round(beat * 60 / bpm * RATE)
            end = cycle * total + round((beat + duration) * 60 / bpm * RATE)
            events.extend([(tick, True, ch, note, vel), (end, False, ch, note, 0)])
    events.sort(key=lambda e: (e[0], e[1]))
    length = total * cycles + (0 if loop else RATE * 3)
    audio = np.zeros((length, 2), dtype=np.float32)
    position = 0
    for tick, is_on, ch, note, vel in events + [(length, False, 0, 0, 0)]:
        tick = min(tick, length)
        if tick > position:
            section = audio[position:tick]
            assert render(synth, len(section), section.ctypes.data, 0, 2, section.ctypes.data, 1, 2) == 0
            position = tick
        (on(synth, ch, note, vel) if is_on else off(synth, ch, note))
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
    gain = min(.68 / max(peak, 1e-8), .105 / max(rms, 1e-8))
    audio *= gain
    ogg(OUT / "music" / f"{name}.ogg", audio)
    midi(WORK / "scores" / f"{name}.mid", score, bpm, beats, instruments)
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

def compose(name, bars):
    score = []
    urgent = name in ["core", "guardian"]
    for bar in range(bars):
        at = bar * 4
        root, chord = HARMONIES[name][bar % 8]
        section = bar // 8
        # Sparse opening, full middle, a contrasting third phrase, then return.
        lead = section != 2 or bar % 2 == 0
        for offset, duration, pitch in MELODIES[name][bar % 8] if lead else []:
            pitch += -12 if section == 2 and name != "guardian" else 0
            note(score, at + offset, duration, 2, pitch, 78 if urgent else 70)
            if name in ["tidal", "garden"]:
                note(score, at + offset + .5, min(.3, duration), 4, pitch, 27)
        # Voiced electric-piano/guitar chords, deliberately syncopated.
        for strike, dur, vel in [(0, 1.25, 55), (1.75, .65, 47), (3, .7, 50)]:
            if name == "tidal" and strike == 1.75 and bar % 2 == 0: continue
            for i, pitch in enumerate(chord):
                note(score, at + strike + i * .012, dur, 0, pitch, vel - i * 2)
        bass_pattern = [(0,.7,root),(1.5,.4,root+7),(2,.65,root+12),(3.5,.4,root+7)]
        if urgent: bass_pattern += [(.75,.3,root),(2.75,.3,root)]
        for offset, dur, pitch in bass_pattern:
            note(score, at + offset, dur, 1, pitch, 77 if offset == 0 else 64)
        if bar % 2 == 0:
            for pitch in chord[:3]: note(score, at, 7.7, 3, pitch, 35)
        # Acoustic/electronic kit with restrained velocity and small swing.
        if section > 0 or name != "title":
            for beat in [0, 2] + ([2.75] if bar % 2 else []): note(score, at + beat, .12, 9, 36, 73)
            for beat in [1, 3]: note(score, at + beat + .012, .12, 9, 38 if urgent else 37, 61)
            for step in range(8):
                note(score, at + step * .5 + (.024 if step % 2 else 0), .08, 9, 42, 39 if step % 2 else 29)
            if name in ["garden", "tidal"]:
                for beat in [.75, 2.25, 3.75]: note(score, at + beat, .1, 9, 75 if name == "garden" else 64, 40)
            if bar % 8 == 7:
                for i in range(4): note(score, at + 3 + i * .25, .1, 9, [45,47,50,38][i], 56 + i * 3)
            if urgent and bar % 8 == 0: note(score, at, .4, 9, 49, 54)
    # Clamp echoed notes to the bar boundary for a valid editable loop file.
    return [(b, min(d, bars * 4 - b - .01), c, n, v) for b,d,c,n,v in score if b < bars * 4 - .02]

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
        audio = render_score(name,title,bpm,bars,instruments,compose(name,bars))
        preview = audio[RATE*8:RATE*20].copy()
        preview[:RATE] *= np.linspace(0,1,RATE)[:,None]
        preview[-RATE:] *= np.linspace(1,0,RATE)[:,None]
        previews.extend([preview,np.zeros((RATE,2),dtype=np.float32)])
    for name,title,pitches,bpm in [("clear","Back to the Surface",[74,78,81,86,85,81,78,86],112),
                                  ("lost","A Light Left Below",[74,72,69,65,64,62],80)]:
        score=[]
        for i,pitch in enumerate(pitches): note(score,i*.5,.6 if i<len(pitches)-1 else 3,2,pitch,70)
        chord=[62,66,69,74] if name=="clear" else [50,57,60,65]
        for pitch in chord: note(score,0,6,0,pitch,55)
        render_score(name,title,bpm,2,{0:4,2:11},score,False)
    count=sfx()
    ogg(WORK/"soundtrack-preview.ogg",np.concatenate(previews))
    (WORK/"score-manifest.json").write_text(json.dumps({"soundfont_sha256":hashlib.sha256((WORK/"GeneralUser-GS.sf2").read_bytes()).hexdigest(),"tracks":manifest,"sound_effects":count},indent=2))
    print(f"Complete: {len(manifest)} music cues, {count} effects, ambience, and preview.",flush=True)
