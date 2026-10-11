# /// script
# dependencies = ["numpy", "soundfile"]
# ///
"""Short-term RMS (dB) of each stem and the master, every half second. usage: uv run audio/lab/levels.py"""
import numpy as np, soundfile as sf
SR = 48000
st = {k: sf.read(f"audio/stems/{k}.wav")[0].mean(axis=1) for k in ("music", "voice", "sfx")}
mix = sf.read("audio/mix.wav")[0].mean(axis=1)
db = lambda x: 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-9)
print("   t   music  voice    sfx    mix")
for t in np.arange(0, len(mix) / SR - 0.25, 0.5):
    a, b = int(t * SR), int((t + 0.5) * SR)
    print(f"{t:5.1f} " + " ".join(f"{db(x[a:b]):6.1f}" for x in (st['music'], st['voice'], st['sfx'], mix)))
