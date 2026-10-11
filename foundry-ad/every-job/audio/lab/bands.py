# /// script
# dependencies = ["numpy", "scipy", "soundfile"]
# ///
"""Per-band level of the sfx stem vs the music+voice bed inside one event's window (from audio/mix-report.json).
usage: uv run audio/lab/bands.py EVENT_ID [EVENT_ID ...]"""
import json, sys
import numpy as np
import soundfile as sf
from scipy import signal

SR = 48000
BANDS = [(125, 250), (250, 500), (500, 1000), (1000, 2000), (2000, 4000), (4000, 8000), (8000, 16000)]
st = {k: sf.read(f"audio/stems/{k}.wav")[0].mean(axis=1) for k in ("music", "voice", "sfx")}
bed = st["music"] + st["voice"]
ev = {e["id"]: e for e in json.load(open("audio/mix-report.json"))["events"]}
def rms(x, lo, hi): return np.sqrt(np.mean(signal.sosfilt(signal.butter(4, [lo, hi], "bandpass", fs=SR, output="sos"), x) ** 2)) + 1e-12
for i in sys.argv[1:]:
    w0, w1 = (int(v * SR) for v in ev[i]["win_s"])
    print(f"{i}  win {ev[i]['win_s']}  solved in {ev[i]['band_hz']}")
    for lo, hi in BANDS:
        s, b, m = rms(st["sfx"][w0:w1], lo, hi), rms(bed[w0:w1], lo, hi), rms(st["music"][w0:w1], lo, hi)
        print(f"  {lo:5d}-{hi:<5d} sfx {20*np.log10(s):6.1f}  bed {20*np.log10(b):6.1f}  lift {20*np.log10(rms(bed[w0:w1] + st['sfx'][w0:w1], lo, hi) / b):5.1f}")
