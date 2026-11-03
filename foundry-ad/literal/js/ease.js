export const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
export const lerp = (a, b, t) => a + (b - a) * t;
export const prog = (t, a, b) => clamp((t - a) / (b - a));
export const smooth = (t) => t * t * (3 - 2 * t);
export const outCubic = (t) => 1 - (1 - t) ** 3;
export const inCubic = (t) => t * t * t;
export const inOutCubic = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);
export const outQuart = (t) => 1 - (1 - t) ** 4;
export const outExpo = (t) => (t >= 1 ? 1 : 1 - 2 ** (-10 * t));
export const inOutQuint = (t) => (t < 0.5 ? 16 * t ** 5 : 1 - (-2 * t + 2) ** 5 / 2);
export const inOutSine = (t) => -(Math.cos(Math.PI * t) - 1) / 2;

export function bezier(x1, y1, x2, y2) {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const sx = (t) => ((ax * t + bx) * t + cx) * t;
  const sy = (t) => ((ay * t + by) * t + cy) * t;
  const dx = (t) => (3 * ax * t + 2 * bx) * t + cx;
  return (x) => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    let t = x;
    for (let i = 0; i < 8; i++) {
      const e = sx(t) - x;
      if (Math.abs(e) < 1e-6) break;
      const d = dx(t);
      if (Math.abs(d) < 1e-6) break;
      t -= e / d;
    }
    return sy(clamp(t));
  };
}

export const brandOut = bezier(0.23, 1, 0.32, 1);

export function hash(i, salt = 0) {
  let h = Math.imul(i ^ (salt * 0x9e3779b1), 0x85ebca6b) ^ 0x5bd1e995;
  h ^= h >>> 15;
  h = Math.imul(h, 0xc2b2ae35);
  h ^= h >>> 13;
  h = Math.imul(h, 0x27d4eb2f);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

export function keys(t, frames, fallbackEase = inOutCubic) {
  if (t <= frames[0][0]) return frames[0][1];
  for (let i = 1; i < frames.length; i++) {
    const [t1, v1, e] = frames[i];
    if (t <= t1) {
      const [t0, v0] = frames[i - 1];
      const u = (e || fallbackEase)(prog(t, t0, t1));
      if (Array.isArray(v0)) return v0.map((a, k) => lerp(a, v1[k], u));
      return lerp(v0, v1, u);
    }
  }
  return frames[frames.length - 1][1];
}
