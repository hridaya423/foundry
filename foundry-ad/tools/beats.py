"""Beat-track audio files with librosa and print tempo, beats, and energy per second.

usage: .venv/bin/python tools/beats.py <audio>...
"""
import sys

import librosa
import numpy as np

for path in sys.argv[1:]:
    y, sr = librosa.load(path, sr=22050, mono=True)
    dur = len(y) / sr
    onset = librosa.onset.onset_strength(y=y, sr=sr)
    tempo, beats = librosa.beat.beat_track(onset_envelope=onset, sr=sr, units="time")
    rms = librosa.feature.rms(y=y)[0]
    rt = librosa.times_like(rms, sr=sr)
    per_s = [round(float(20 * np.log10(rms[(rt >= s) & (rt < s + 1)].mean() + 1e-9)), 1) for s in range(int(dur))]
    ibi = np.diff(beats)
    print(f"== {path}  dur={dur:.2f}s tempo={float(np.atleast_1d(tempo)[0]):.2f}  ibi median={np.median(ibi):.4f} std={ibi.std():.4f}")
    print("  beats:", [round(float(b), 3) for b in beats])
    print("  dB/s :", per_s)
