import subprocess
import sys

import numpy as np

args = [a for a in sys.argv[1:] if not a.startswith("--")]
video = args[0]
fps = float(args[1]) if len(args) > 1 else 60.0
allowed = [float(t) for a in sys.argv[1:] if a.startswith("--allow=") for t in a[8:].split(",")]
w, h = 240, 135
raw = subprocess.run(
    ["ffmpeg", "-v", "error", "-i", video, "-vf", f"scale={w}:{h},format=gray", "-f", "rawvideo", "-"],
    capture_output=True,
    check=True,
).stdout
frames = np.frombuffer(raw, dtype=np.uint8).reshape(-1, h, w).astype(np.float32)
diff = np.abs(np.diff(frames, axis=0)).mean(axis=(1, 2))
seam = float(np.abs(frames[0] - frames[-1]).mean())
pops = []
for i, d in enumerate(diff):
    around = np.concatenate([diff[max(0, i - 4) : i], diff[i + 1 : i + 5]])
    base = float(np.median(around)) if len(around) else 0.0
    if d > 4.0 and d > 4.0 * max(base, 0.5) and not any(abs((i + 1) / fps - t) < 1.5 / fps for t in allowed):
        pops.append((i + 1, float(d), base))
print(f"frames {len(frames)}  median change {np.median(diff):.2f}  loop seam {seam:.2f}")
for n, d, base in pops:
    print(f"pop at frame {n} ({n / fps:.3f}s): change {d:.1f} vs neighbours {base:.1f}")
sys.exit(1 if pops or seam > 4.0 * float(np.median(diff)) + 1.0 else 0)
