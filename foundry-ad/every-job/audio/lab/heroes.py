# /// script
# dependencies = ["numpy", "soundfile"]
# ///
"""How hard each hero hits in the master: peak and 100 ms RMS right after the cue, against the film's loudest
100 ms. Heroes should be the loudest moments. usage: uv run audio/lab/heroes.py"""
import json
import numpy as np
import soundfile as sf

SR = 48000
mix = sf.read("audio/mix.wav")[0].mean(axis=1)
n = int(0.1 * SR)
rms = np.sqrt(np.convolve(mix ** 2, np.ones(n) / n, mode="valid"))
db = lambda v: 20 * np.log10(v + 1e-9)
print(f"loudest 100 ms in the film: {db(rms.max()):.1f} dB at {np.argmax(rms) / SR:.2f}s")
for e in json.load(open("audio/mix-report.json"))["events"]:
    if e["weight"] != "hero": continue
    i = int(e["peak_s"] * SR)
    print(f"{e['id']:16s} {e['peak_s']:6.2f}s  peak {db(np.abs(mix[i - 480:i + 4800]).max()):6.1f}  rms100 {db(rms[max(0, i - 480):i + 2400].max()):6.1f}"
          f"  gain {e['gain_db']:6.1f} ({e['limited_by']})")
