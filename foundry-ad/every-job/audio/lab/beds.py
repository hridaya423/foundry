# /// script
# dependencies = ["numpy", "scipy"]
# ///
"""The roar beds against the score, before the stems are mixed: level (dB, 50 ms windows) of the score, the beds and
the beds' share above 4 kHz and below 250 Hz, and the beds' stereo width (side over mid).
usage: BEDS_DEBUG=1 uv run tools/score.py && uv run audio/lab/beds.py T0 T1 [STEP]"""
import sys
import numpy as np
from scipy import signal
SR = 48000
z = np.load("audio/lab/beds-debug.npz"); m, b = z["music"], z["beds"]
t0, t1 = float(sys.argv[1]), float(sys.argv[2]); dt = float(sys.argv[3]) if len(sys.argv) > 3 else 0.05
db = lambda x: 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
hp = lambda x: signal.sosfilt(signal.butter(4, 4000, "highpass", fs=SR, output="sos"), x)
lp = lambda x: signal.sosfilt(signal.butter(4, 250, "lowpass", fs=SR, output="sos"), x)
mm, bm = m.mean(1), b.mean(1); mh, bh, ml, bl = hp(mm), hp(bm), lp(mm), lp(bm)
print("     t  score   beds  sc>4k beds>4k sc<250 bds<250  beds S/M")
for t in np.arange(t0, t1, dt):
    a, c = int(t * SR), int((t + dt) * SR)
    S, M = (b[a:c, 0] - b[a:c, 1]) / 2, (b[a:c, 0] + b[a:c, 1]) / 2
    print(f"{t:6.2f} {db(mm[a:c]):6.1f} {db(bm[a:c]):6.1f} {db(mh[a:c]):6.1f} {db(bh[a:c]):6.1f} {db(ml[a:c]):6.1f} {db(bl[a:c]):6.1f} {db(S) - db(M):8.1f}")
