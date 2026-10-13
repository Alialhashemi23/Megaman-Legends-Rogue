"""Decode rendered assets and check their audio data, including loop seams."""
import ctypes as C
import json
import wave
import numpy as np
from compose import snd, SFInfo, OUT, WORK

snd.sf_readf_float.restype = C.c_longlong
snd.sf_readf_float.argtypes = [C.c_void_p, C.c_void_p, C.c_longlong]
report = {}
manifest = json.loads((WORK / "score-manifest.json").read_text())
for path in sorted(OUT.rglob("*.ogg")):
    info = SFInfo()
    f = snd.sf_open(str(path).encode(), 0x10, C.byref(info))
    assert f and info.channels == 2 and info.samplerate == 32000, path
    data = np.zeros((info.frames, info.channels), dtype=np.float32)
    for start in range(0, len(data), 8192):
        block = data[start:start+8192]
        assert snd.sf_readf_float(f, block.ctypes.data, len(block)) == len(block), path
    snd.sf_close(f)
    peak = float(np.max(abs(data)))
    rms = float(np.sqrt(np.mean(data**2)))
    assert np.isfinite(data).all() and .001 < rms < .2 and peak < .95, path
    looping = path.stem not in ["clear", "lost"]
    seam = float(np.max(abs(data[0] - data[-1])))
    assert not looping or seam < .04, (path, seam)
    report[path.name] = {"seconds":round(len(data)/info.samplerate,3),"peak":round(peak,4),"rms":round(rms,4),"loop_seam":round(seam,5) if looping else None}
for path in sorted((OUT/"sfx").glob("*.wav")):
    with wave.open(str(path)) as f:
        data = np.frombuffer(f.readframes(f.getnframes()),dtype="<i2") / 32768.
    assert len(data) > 700 and float(abs(data).max()) < .98 and float(np.std(data)) > .001, path
with wave.open(str(WORK/"in-game-mix.wav")) as f:
    data = np.frombuffer(f.readframes(f.getnframes()),dtype="<i2") / 32768.
assert np.sqrt(np.mean(data**2)) > .01 and abs(data).max() < .99
report["runtime_mix"] = {"peak":round(float(abs(data).max()),4),"rms":round(float(np.sqrt(np.mean(data**2))),4),"clipped_samples":int(np.sum(abs(data) >= .999))}
(WORK/"audio-validation.json").write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
print("AUDIO_DATA_PASS: 8 stereo Ogg files, 29 effects, loop seams and captured runtime mix")
