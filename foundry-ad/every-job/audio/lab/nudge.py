# /// script
# dependencies = ["numpy", "scipy", "soundfile"]
# ///
"""What a sub-frame nudge of one hero would do: shift the sfx stem by d ms inside the event's window and report its
main-band lift over music+voice (QA's hero body, needs 3 dB) and the correlation below 250 Hz (negative = cancels).
Approximate: mix.py re-levels the hit when it moves. usage: uv run audio/lab/nudge.py EVENT_ID [LO HI]"""
import json, sys
import numpy as np, soundfile as sf
from scipy import signal
SR = 48000
st = {k: sf.read(f"audio/stems/{k}.wav")[0].mean(axis=1) for k in ("music", "voice", "sfx")}
bed = st["music"] + st["voice"]
ev = {e["id"]: e for e in json.load(open("audio/mix-report.json"))["events"]}[sys.argv[1]]
lo, hi = (float(sys.argv[2]), float(sys.argv[3])) if len(sys.argv) > 3 else ev["band_hz"]
w0, w1 = (int(v * SR) for v in ev["win_s"])
bp = lambda x, a, b: signal.sosfilt(signal.butter(4, [a, b], "bandpass", fs=SR, output="sos"), x)
B, BL = bp(bed, lo, hi)[w0:w1], bp(bed, 40, 250)[w0:w1]
S, SL = bp(st["sfx"], lo, hi), bp(st["sfx"], 40, 250)
r = lambda x: np.sqrt(np.mean(x ** 2)) + 1e-12
for d in range(-8, 9):
    k = int(d * SR / 1000); s, sl = S[w0 - k:w1 - k], SL[w0 - k:w1 - k]
    print(f"{d:+3d} ms  lift {20 * np.log10(r(B + s) / r(B)):5.2f} dB in {lo:.0f}-{hi:.0f}   corr<250 {np.corrcoef(sl, BL)[0, 1]:+.2f}")
