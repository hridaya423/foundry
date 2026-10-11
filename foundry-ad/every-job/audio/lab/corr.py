# /// script
# dependencies = ["numpy", "soundfile"]
# ///
"""Correlation between the sfx stem and the bed in a window: near -1 means one cancels the other.
usage: uv run audio/lab/corr.py T0 T1"""
import sys
import numpy as np
import soundfile as sf
SR = 48000
st = {k: sf.read(f"audio/stems/{k}.wav")[0] for k in ("music", "voice", "sfx")}
a, b = (int(float(v) * SR) for v in sys.argv[1:3])
for ch in (0, 1):
    s, m = st["sfx"][a:b, ch], st["music"][a:b, ch] + st["voice"][a:b, ch]
    print(f"ch{ch} corr {np.corrcoef(s, m)[0, 1]:+.3f}  sfx rms {20*np.log10(np.std(s)+1e-12):.1f}  bed rms {20*np.log10(np.std(m)+1e-12):.1f}")
