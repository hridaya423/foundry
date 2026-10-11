#!/usr/bin/env python3
"""Renders the typing takes planned by tools/cues.py (audio/takes.json): real key recordings from the sound-layer kit,
one per stroke, at the times the characters appear on screen. One file per command, so mix.py places each burst as
one event on its accented stroke.

usage: uv run tools/takes.py   -> audio/own/take-*.wav
"""
# /// script
# dependencies = ["numpy", "soundfile"]
# ///
import json, os
import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 48000
KIT = os.path.join(ROOT, "audio", "kit")
cat = {e["id"]: e for e in json.load(open(os.path.join(KIT, "catalog.json")))["sounds"]}

def one_shot(kid):
    x, sr = sf.read(os.path.join(KIT, cat[kid]["file"]))
    assert sr == SR, kid
    x = x.mean(axis=1) if x.ndim > 1 else x
    return x / (np.abs(x).max() + 1e-12)

for take in json.load(open(os.path.join(ROOT, "audio", "takes.json"))):
    t_first = min(t for t, _, _ in take["strokes"])
    shots = [(int(round((t - t_first) * SR)), one_shot(kid) * g) for t, kid, g in take["strokes"]]
    out = np.zeros(max(i + len(x) for i, x in shots))
    for i, x in shots: out[i:i + len(x)] += x
    path = os.path.join(ROOT, "audio", "own", take["name"] + ".wav")
    sf.write(path, (out / np.abs(out).max() * 0.7).astype(np.float32), SR, subtype="FLOAT")
    print(f"{take['name']:16s} {len(take['strokes'])} strokes -> {os.path.relpath(path, ROOT)}")
