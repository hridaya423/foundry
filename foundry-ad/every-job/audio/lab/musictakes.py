# /// script
# dependencies = ["numpy", "librosa", "soundfile", "matplotlib"]
# ///
"""Score music takes (audio/music/take-*.mp3) against the film: tempo and lock to the 0.5 s grid, how hard the drop
lands on MELT_CMD, and whether the energy follows the story. Writes audio/music/takes.png.
usage: uv run audio/lab/musictakes.py"""
import glob, os, sys
import numpy as np, librosa
import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools")); import timing as T

HOP = 0.05
def env(y, sr):
    r = librosa.feature.rms(y=y, frame_length=int(sr * 0.2), hop_length=int(sr * HOP))[0]
    db = 20 * np.log10(r + 1e-6); return db - db.max()
def mean(db, a, b): return float(db[int(a / HOP):int(b / HOP)].mean())

rows = []
fig, ax = plt.subplots(figsize=(14, 6))
for f in sorted(glob.glob(os.path.join(ROOT, "audio/music/take-*.mp3")), key=lambda p: int(p.split("-")[-1][:-4])):
    y, sr = librosa.load(f, sr=22050, mono=True)
    db = env(y, sr)
    tempo, beats = librosa.beat.beat_track(y=y, sr=sr, start_bpm=120, units="time")
    tempo = float(np.atleast_1d(tempo)[0])
    lock = float(np.median(np.abs(((beats + 0.25) % 0.5) - 0.25))) * 1000 if len(beats) else 999   # ms off the grid
    on = librosa.onset.onset_strength(y=y, sr=sr, hop_length=256); ot = librosa.times_like(on, sr=sr, hop_length=256)
    w = (ot > T.MELT_CMD - 0.06) & (ot < T.MELT_CMD + 0.06)
    drop = float(on[w].max() / (np.median(on) + 1e-6))                                     # onset strength at the drop
    jump = mean(db, T.MELT_CMD, T.MELT_CMD + 1.0) - mean(db, 3.0, T.STALL)                  # louder than the weight
    s = {"lineage": mean(db, 0.3, 2.8), "weight0": mean(db, 3.0, 4.2), "weight1": mean(db, 4.6, T.STALL),
         "drop": mean(db, T.MELT_CMD, T.MELT_CMD + 2.0), "settle": mean(db, T.CAST + 0.5, 11.8), "build0": mean(db, 12.0, 14.0),
         "build1": mean(db, 16.5, 18.6), "leap": mean(db, 19.2, 22.5), "swell": mean(db, 23.0, 24.8)}
    story = sum([s["lineage"] < s["drop"] - 6, s["weight1"] > s["weight0"] + 1, s["drop"] > -6, s["settle"] < s["drop"] - 3,
                 s["build1"] > s["build0"], s["leap"] < s["build1"] - 6, s["swell"] > s["leap"] + 3])
    score = story * 10 + min(drop, 8) * 3 + max(0, 12 - abs(tempo - 120)) - lock / 10
    rows.append((os.path.basename(f), tempo, lock, drop, jump, story, s, score))
    ax.plot(np.arange(len(db)) * HOP, db, lw=0.9, label=os.path.basename(f)[:-4])
for _, t in T.MUSIC: ax.axvline(t, color="k", lw=0.6, ls="--")
ax.axvspan(T.STALL, T.MELT_CMD, color="0.85", label="valley (cut in the edit)")
ax.set_xlabel("s"); ax.set_ylabel("dB (0 = loudest)"); ax.set_ylim(-45, 2); ax.legend(ncol=4, fontsize=8)
plt.tight_layout(); plt.savefig(os.path.join(ROOT, "audio/music/takes.png"), dpi=110)

print(f"{'take':12s} {'bpm':>6s} {'grid ms':>8s} {'drop x':>7s} {'jump dB':>8s} {'story/7':>8s}   lineage weight0 weight1 drop settle build0 build1 leap swell   score")
for n, tempo, lock, drop, jump, story, s, score in sorted(rows, key=lambda r: -r[-1]):
    print(f"{n:12s} {tempo:6.1f} {lock:8.0f} {drop:7.1f} {jump:8.1f} {story:8d}   " + " ".join(f"{v:6.1f}" for v in s.values()) + f"   {score:5.1f}")
