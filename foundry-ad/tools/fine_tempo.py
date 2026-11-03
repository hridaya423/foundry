"""Measure tempo and beat phase precisely: fine onset envelope, autocorrelation with
parabolic peak interpolation, then least-squares fit of a beat grid to detected onsets.

usage: .venv/bin/python tools/fine_tempo.py <audio> [start_s end_s]
"""
import sys

import librosa
import numpy as np

path = sys.argv[1]
a = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
b = float(sys.argv[3]) if len(sys.argv) > 3 else None
SR, HOP = 44100, 64
y, _ = librosa.load(path, sr=SR, mono=True, offset=a, duration=None if b is None else b - a)
low = librosa.effects.preemphasis(y, coef=-0.97)  # emphasize lows for kick onsets
env = librosa.onset.onset_strength(y=low, sr=SR, hop_length=HOP, fmax=200, n_mels=32)
env = env - env.mean()
ac = np.correlate(env, env, "full")[len(env) - 1:]
fps = SR / HOP
lo, hi = int(fps * 60 / 150), int(fps * 60 / 110)
k = lo + int(np.argmax(ac[lo:hi]))
y0, y1, y2 = ac[k - 1], ac[k], ac[k + 1]
k_f = k + 0.5 * (y0 - y2) / (y0 - 2 * y1 + y2)
period = k_f / fps
on = librosa.onset.onset_detect(onset_envelope=env + abs(env.min()), sr=SR, hop_length=HOP, units="time", backtrack=False)
# phase: fold onsets onto the period and take circular mean weighted by strength
ph = np.angle(np.exp(2j * np.pi * on / period).mean()) / (2 * np.pi) * period % period
# refine period + phase by regression on onsets that sit within 15% of a grid line
for _ in range(3):
    n = np.round((on - ph) / period)
    near = np.abs(on - (ph + n * period)) < 0.15 * period
    A = np.vstack([n[near], np.ones(near.sum())]).T
    period, ph = np.linalg.lstsq(A, on[near], rcond=None)[0]
resid = on[near] - (ph + n[near] * period)
print(f"{path} [{a}-{b}] bpm={60 / period:.3f} period={period:.5f}s first_beat={a + ph:.4f}s "
      f"fit_onsets={near.sum()} resid_ms={1000 * np.abs(resid).mean():.1f}")
