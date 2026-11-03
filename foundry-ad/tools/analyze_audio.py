"""Analyze a music file: energy envelopes, onsets, tempo, and a spectrogram sheet.

usage: python3 tools/analyze_audio.py <audio> <out-prefix>
"""
import json
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import signal

SR = 22050
HOP = 220  # 10 ms


def load(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
        capture_output=True, check=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.float32)


def frames(x, n=2048):
    pad = np.pad(x, (n // 2, n // 2))
    count = 1 + (len(pad) - n) // HOP
    idx = np.arange(n)[None, :] + HOP * np.arange(count)[:, None]
    return pad[idx] * np.hanning(n)[None, :]


def main():
    path, out = sys.argv[1], sys.argv[2]
    x = load(path)
    spec = np.abs(np.fft.rfft(frames(x), axis=1))
    freqs = np.fft.rfftfreq(2048, 1 / SR)
    t = np.arange(spec.shape[0]) * HOP / SR

    rms = np.sqrt((frames(x, 1024) ** 2).mean(axis=1))[: len(t)]
    low = spec[:, (freqs > 30) & (freqs < 150)].sum(axis=1)
    high = spec[:, freqs > 5000].sum(axis=1)
    logspec = np.log1p(spec)
    flux = np.maximum(0, np.diff(logspec, axis=0)).sum(axis=1)
    flux = np.concatenate([[0], flux])
    lowflux = np.maximum(0, np.diff(np.log1p(spec[:, freqs < 150]), axis=0)).sum(axis=1)
    lowflux = np.concatenate([[0], lowflux])

    def peaks(env, rel, dist_s):
        env = env / (env.max() + 1e-9)
        p, _ = signal.find_peaks(env, height=rel, distance=int(dist_s * SR / HOP))
        return [round(float(t[i]), 3) for i in p], [round(float(env[i]), 3) for i in p]

    onsets, onset_h = peaks(flux, 0.25, 0.08)
    kicks, kick_h = peaks(lowflux, 0.3, 0.2)

    def tempo(a, b):
        sel = (t >= a) & (t < b)
        env = lowflux[sel] - lowflux[sel].mean()
        ac = np.correlate(env, env, "full")[len(env) - 1:]
        lags = np.arange(len(ac)) * HOP / SR
        ok = (lags > 60 / 180) & (lags < 60 / 70)
        best = lags[ok][np.argmax(ac[ok])]
        return round(60 / best, 2)

    dur = len(x) / SR
    win = 0.5
    seg = []
    for a in np.arange(0, dur, win):
        sel = (t >= a) & (t < a + win)
        seg.append({
            "t": round(float(a), 2),
            "rms_db": round(float(20 * np.log10(rms[sel].mean() + 1e-9)), 1),
            "low": round(float(low[sel].mean() / low.max()), 3),
            "high": round(float(high[sel].mean() / high.max()), 3),
        })

    report = {
        "duration": round(dur, 3),
        "tempo_drive": tempo(6, 13) if dur > 13 else None,
        "kicks": list(zip(kicks, kick_h)),
        "onsets": list(zip(onsets, onset_h)),
        "segments": seg,
    }
    json.dump(report, open(out + ".json", "w"), indent=1)

    # spectrogram sheet with rms + kick markers
    W, H = 2000, 520
    img = np.log1p(spec[:, freqs < 11000]).T[::-1]
    img = (255 * (img - img.min()) / (img.max() - img.min())) ** 1.0
    im = Image.fromarray(img.astype(np.uint8)).resize((W, 360))
    sheet = Image.new("RGB", (W, H), "black")
    sheet.paste(im.convert("RGB"), (0, 0))
    d = ImageDraw.Draw(sheet)
    r = rms / rms.max()
    pts = [(int(i / len(r) * W), int(500 - r[i] * 130)) for i in range(0, len(r), 2)]
    d.line(pts, fill=(255, 120, 40), width=2)
    for k in kicks:
        X = int(k / dur * W)
        d.line([(X, 360), (X, 380)], fill=(80, 200, 255), width=2)
    for s in range(int(dur) + 1):
        X = int(s / dur * W)
        d.line([(X, 0), (X, H)], fill=(90, 90, 90), width=1)
        d.text((X + 3, 382), str(s), fill=(230, 230, 230))
    sheet.save(out + ".png")
    print(json.dumps({k: report[k] for k in ("duration", "tempo_drive")}))
    print("kicks:", kicks)
    print("segments rms_db:", [(s["t"], s["rms_db"]) for s in seg])


if __name__ == "__main__":
    main()
