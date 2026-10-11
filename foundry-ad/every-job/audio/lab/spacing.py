"""Support events whose real peak (from audio/mix-report.json) lands within 0.15 s of the previous event's peak:
mix.py turns those down by 4.4 dB. usage: python3 audio/lab/spacing.py"""
import json

ev = sorted(json.load(open("audio/mix-report.json"))["events"], key=lambda e: e["peak_s"])
for a, b in zip(ev, ev[1:]):
    if b["peak_s"] - a["peak_s"] < 0.15 and b["weight"] != "hero":
        print(f"{b['id']:20s} {b['peak_s']:7.3f}  {b['peak_s'] - a['peak_s']:.3f}s after {a['id']}")
