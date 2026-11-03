#!/usr/bin/env python3
"""Renders the typing takes planned by tools/cues.py (audio/takes.json): the computed keys of tools/sfx.py (or kit
recordings), one per stroke, at the times the characters appear on screen. One file per command, so mix.py places each burst as
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
    x, sr = sf.read(os.path.join(ROOT, kid) if kid.endswith(".wav") else os.path.join(KIT, cat[kid]["file"]))
    assert sr == SR, kid
    x = x.mean(axis=1) if x.ndim > 1 else x
    return x / (np.abs(x).max() + 1e-12)

for take in json.load(open(os.path.join(ROOT, "audio", "takes.json"))):
    t_first = min(t for t, _, _ in take["strokes"])
    shots = [(int(round((t - t_first) * SR)), one_shot(kid) * g) for t, kid, g in take["strokes"]]
    out = np.zeros(max(i + len(x) for i, x in shots))
    for i, x in shots: out[i:i + len(x)] += x
    # mix.py places a take by its loudest 2 ms (its peak_offset): that must be the accented stroke, or the whole take
    # lands early or late by the distance between the two
    acc = next(i for (i, _), (_, _, g) in zip(shots, take["strokes"]) if g == 1.0)
    w = int(0.002 * SR)
    pk = int(np.argmax(np.sqrt(np.convolve(out * out, np.ones(w) / w, mode="same"))))
    assert acc <= pk < acc + int(0.05 * SR), f"{take['name']}: loudest at {pk / SR:.3f} s, accent at {acc / SR:.3f} s"
    path = os.path.join(ROOT, "audio", "own", take["name"] + ".wav")
    sf.write(path, (out / np.abs(out).max() * 0.7).astype(np.float32), SR, subtype="FLOAT")
    print(f"{take['name']:16s} {len(take['strokes'])} strokes -> {os.path.relpath(path, ROOT)}")
