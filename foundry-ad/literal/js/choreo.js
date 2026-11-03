import * as THREE from "three";
import { clamp, lerp, prog, smooth, outCubic, inOutCubic, outQuart, outExpo, brandOut, hash, keys } from "./ease.js";
import { PITCH as P } from "./tiles.js";

const TM = window.TM;
const D = window.DATA;
const COLS = D.cols;
const ROWS = D.rows;
const N = COLS * ROWS;

const gx = (c) => (c - (COLS - 1) / 2) * P;
const gy = (r) => ((ROWS - 1) / 2 - r) * P;

const srgb = (hex) => new THREE.Color(hex);
export const PALETTE = {
  chalk: srgb("#c6bbab"),
  orange: srgb("#ef672e"),
  ink: srgb("#0f0d0c"),
  checkA: srgb("#1a1715"),
  checkB: srgb("#24201c"),
};

const CENTER = { x: 6 * P, y: 0.5 * P };
const PARK_Y = -1500;
const G_FALL = 2600;

const orange = [];
const background = [];
for (let i = 0; i < N; i++) (D.wall[i][0] === 1 ? orange : background).push(i);

const wallColor = (i) => new THREE.Color(D.wall[i][1], D.wall[i][2], D.wall[i][3]);

function orangeDistance() {
  const isOrange = new Uint8Array(N);
  orange.forEach((i) => (isOrange[i] = 1));
  const dist = new Float32Array(N).fill(1e9);
  const pts = orange.map((i) => [i % COLS, Math.floor(i / COLS)]);
  for (const i of background) {
    const c = i % COLS, r = Math.floor(i / COLS);
    let best = 1e9;
    for (const [oc, or] of pts) {
      const d = (oc - c) ** 2 + (or - r) ** 2;
      if (d < best) best = d;
    }
    dist[i] = Math.sqrt(best);
  }
  return dist;
}
const DIST = orangeDistance();
const MAX_DIST = Math.max(...background.map((i) => DIST[i]));

const blockSlot = (k) => ({ x: CENTER.x + ((k % 24) - 11.5) * P, y: CENTER.y + (8.5 - Math.floor(k / 24)) * P });
const stripSlot = (sc, sr) => ({ x: CENTER.x + (sc - 23.5) * P, y: CENTER.y + (4 - sr) * P });
const blockToStrip = (k) => {
  const bc = k % 24, br = Math.floor(k / 24);
  return br < 9 ? { sc: bc, sr: br } : { sc: bc + 24, sr: br - 9 };
};

const orangeOrder = orange.slice().sort((a, b) => Math.floor(a / COLS) - Math.floor(b / COLS) || (a % COLS) - (b % COLS));
const blockIndex = new Int32Array(N).fill(-1);
orangeOrder.forEach((i, k) => (blockIndex[i] = k));

const QR = D.qr.matrix;
const QN = QR.length;
const QZ = 4;
const QS = QN + 2 * QZ;
const QR_CENTER = { x: CENTER.x, y: CENTER.y };
const qrDark = (qc, qr) => {
  const c = qc - QZ, r = qr - QZ;
  return c >= 0 && r >= 0 && c < QN && r < QN && QR[r][c] === 1;
};
const qrSlot = (q) => ({ x: QR_CENTER.x + ((q % QS) - (QS - 1) / 2) * P, y: QR_CENTER.y + ((QS - 1) / 2 - Math.floor(q / QS)) * P });

const qrAssign = new Int32Array(N).fill(-1);
const qrPoolIndex = new Int32Array(N).fill(-1);
(function assignQR() {
  const darkSlots = [], lightSlots = [];
  for (let q = 0; q < QS * QS; q++) (qrDark(q % QS, Math.floor(q / QS)) ? darkSlots : lightSlots).push(q);
  const stripTiles = orangeOrder.slice();
  const byX = (list, f) => list.slice().sort((a, b) => f(a) - f(b));
  const stripPos = (i) => {
    const s = blockToStrip(blockIndex[i]);
    return stripSlot(s.sc, s.sr);
  };
  const orangeSlots = darkSlots.slice();
  const extraLight = [];
  while (orangeSlots.length < stripTiles.length) orangeSlots.push(lightSlots.splice(Math.floor(lightSlots.length / 2), 1)[0]);
  const sortedSlots = byX(orangeSlots, (q) => qrSlot(q).x * 10 + qrSlot(q).y * 0.01);
  const sortedTiles = byX(stripTiles, (i) => stripPos(i).x * 10 + stripPos(i).y * 0.01);
  const used = new Set();
  sortedTiles.forEach((i, k) => {
    qrAssign[i] = sortedSlots[k];
    used.add(sortedSlots[k]);
  });
  const remaining = [];
  for (let q = 0; q < QS * QS; q++) if (!used.has(q)) remaining.push(q);
  remaining.sort((a, b) => Math.floor(b / QS) - Math.floor(a / QS) || (a % QS) - (b % QS));
  const pool = background.slice().sort((a, b) => hash(a, 7) - hash(b, 7));
  remaining.forEach((q, k) => {
    qrAssign[pool[k]] = q;
    qrPoolIndex[pool[k]] = k;
  });
  extraLight.length = 0;
})();
const QR_POOL_COUNT = QS * QS - orange.length;

const WM = D.wordmark;
const WM_CX = 880;
const WM_CY = 296;
const STOP = [
  { x: 1652, y: 380.6, w: 30, h: 28.5 },
  { x: 1682, y: 380.6, w: 30, h: 28.5 },
  { x: 1652, y: 352.1, w: 30, h: 28.5 },
  { x: 1682, y: 352.1, w: 30, h: 28.5 },
];
export const WORDMARK = WM.map((t) => ({ ...t, wx: t.x - WM_CX, wy: -(t.y - WM_CY), stop: false })).concat(
  STOP.map((s, k) => {
    const hw = s.w / 2 - 0.2, hh = s.h / 2 - 0.2;
    return {
      id: `stop-${k}`, full: true, x: s.x, y: s.y, width: s.w, height: s.h,
      polygons: [[[s.x - hw, s.y - hh], [s.x + hw, s.y - hh], [s.x + hw, s.y + hh], [s.x - hw, s.y + hh], [s.x - hw, s.y - hh]]],
      wx: s.x - WM_CX, wy: -(s.y - WM_CY), stop: true,
    };
  }),
);
const WN = WORDMARK.length;

const qrTiles = [];
for (let i = 0; i < N; i++) if (qrAssign[i] >= 0) qrTiles.push(i);
const wmSource = new Int32Array(WN);
(function assignWordmark() {
  const letters = WORDMARK.map((t, k) => k).filter((k) => !WORDMARK[k].stop);
  const sortedSlots = letters.slice().sort((a, b) => WORDMARK[a].wx - WORDMARK[b].wx);
  const candidates = qrTiles.slice().sort((a, b) => qrSlot(qrAssign[a]).x - qrSlot(qrAssign[b]).x);
  const step = candidates.length / sortedSlots.length;
  sortedSlots.forEach((k, n) => (wmSource[k] = candidates[Math.floor(n * step)]));
  const stops = WORDMARK.map((t, k) => k).filter((k) => WORDMARK[k].stop);
  const center = orangeOrder[Math.floor(orangeOrder.length / 2)];
  stops.forEach((k, n) => (wmSource[k] = orangeOrder[(Math.floor(orangeOrder.length / 2) + n * 7) % orangeOrder.length]));
  void center;
})();
const wmTaken = new Uint8Array(N);
wmSource.forEach((i) => (wmTaken[i] = 1));

const landEnd = (k) => {
  const t = WORDMARK[k];
  if (t.stop) return TM.period;
  const u = (t.wx + WM_CX - 60) / 1600;
  return lerp(TM.land[0], TM.land[1], clamp(0.75 * u + 0.25 * hash(k, 31)));
};

function hingeFall(out, x, y, t0, t, i) {
  const tip = 0.16;
  const u = t - t0;
  if (u <= 0) return false;
  const a0 = 0.5;
  const r = P / 2;
  if (u < tip) {
    const a = a0 * (u / tip) ** 2;
    out.x = x;
    out.y = y - r + r * Math.cos(a);
    out.z = -r * Math.sin(a);
    out.rx = -a;
    return true;
  }
  const s = u - tip;
  const w = (2 * a0) / tip;
  const vy = -r * w * Math.sin(a0);
  const vz = -r * w * Math.cos(a0) - 30 * hash(i, 3);
  const vx = (hash(i, 4) - 0.5) * 40;
  out.x = x + vx * s;
  out.y = y - r + r * Math.cos(a0) + vy * s - 0.5 * G_FALL * s * s;
  out.z = -r * Math.sin(a0) + vz * s;
  out.rx = -(a0 + w * (0.5 + 0.3 * hash(i, 5)) * s);
  out.ry = (hash(i, 6) - 0.5) * 1.2 * s;
  out.rz = (hash(i, 8) - 0.5) * 1.6 * s;
  return true;
}

const cascadeStart = (i) => TM.cascade[0] + 0.06 + (DIST[i] / MAX_DIST) * 1.55 + (hash(i, 2) - 0.5) * 0.08;

const DRAG = 1.35;
const G_CONF = 1700;
const VT = -G_CONF / DRAG;
const POOL_FLY = 0.15;
const CHAFF_FALL = 0.85;
const G_CHAFF = 2600;
export const flies = (i) => hash(i, 49) < POOL_FLY;
function confettiState(i, t, origin, out, vel) {
  const s = Math.max(0, t - TM.drop);
  const r1 = hash(i, 41), r2 = hash(i, 42), r3 = hash(i, 43), r4 = hash(i, 44);
  let vx, vy, vz;
  if (origin.qr) {
    const dx = origin.x - QR_CENTER.x, dy = origin.y - QR_CENTER.y;
    const len = Math.hypot(dx, dy) + 1e-3;
    const burst = 700 + 1500 * r1 ** 0.7;
    vx = (dx / len) * burst * 0.9 + (r2 - 0.5) * 260;
    vy = (dy / len) * burst * 0.75 + 1250 + 600 * r2;
    vz = 400 + 900 * r3 ** 1.5;
  } else {
    vx = (r1 - 0.5) * 900;
    vy = 4300 + 1500 * r2;
    vz = (r3 - 0.5) * 300;
  }
  const e = Math.exp(-DRAG * s);
  const k = (1 - e) / DRAG;
  out.x = origin.x + vx * k;
  out.y = origin.y + VT * s + (vy - VT) * k;
  out.z = origin.z + vz * k;
  const late = wmTaken[i] ? 0 : Math.max(0, s - CHAFF_FALL);
  out.y -= 0.5 * G_CHAFF * late * late;
  if (vel) {
    vel.x = vx * e;
    vel.y = VT + (vy - VT) * e - G_CHAFF * late;
    vel.z = vz * e;
  }
  const rate = 3 + 8 * r4;
  out.ax = hash(i, 45) - 0.5;
  out.ay = hash(i, 46) - 0.5;
  out.az = hash(i, 47) - 0.5;
  out.angle = rate * (s * 0.55 + 0.45 * k);
}

const _q = new THREE.Quaternion();
const _e = new THREE.Euler();
const _axis = new THREE.Vector3();

function quatFromState(st, q) {
  if (st.angle !== undefined) {
    _axis.set(st.ax, st.ay, st.az);
    if (_axis.lengthSq() < 1e-6) _axis.set(0, 1, 0);
    _axis.normalize();
    q.setFromAxisAngle(_axis, st.angle);
  } else {
    _e.set(st.rx || 0, st.ry || 0, st.rz || 0);
    q.setFromEuler(_e);
  }
  return q;
}

function flipAngle(t, t0, dur) {
  return Math.PI * smooth(prog(t, t0, t0 + dur));
}

const HIDE = { hidden: true };

function preDropPose(i, t, st) {
  st.x = gx(i % COLS);
  st.y = gy(Math.floor(i / COLS));
  st.z = 0;
  st.rx = st.ry = st.rz = 0;
  st.angle = undefined;
  st.flipAxis = 0;
  st.flip = 0;
  st.face = null;
  st.back = null;
  st.qr = false;
  const isOrange = blockIndex[i] >= 0;
  if (!isOrange) {
    const t0 = cascadeStart(i);
    if (t >= t0) {
      if (qrAssign[i] >= 0 && t >= TM.qr.enter - 0.2) return qrPoolPose(i, t, st);
      const moving = hingeFall(st, st.x, st.y, t0, t, i);
      if (moving && st.y < -1300) return HIDE;
    }
    return st;
  }
  const k = blockIndex[i];
  const [s0, s1] = TM.square;
  if (t >= s0) {
    const from = { x: st.x, y: st.y };
    const to = blockSlot(k);
    const delay = 0.16 * (Math.floor(k / 24) / 17) + 0.02 * hash(i, 11);
    const u = brandOut(prog(t, s0 + delay, s0 + delay + 0.34));
    st.x = lerp(from.x, to.x, u);
    st.y = lerp(from.y, to.y, u);
    st.z = 36 * Math.sin(Math.PI * u);
  }
  const bc = k % 24, br = Math.floor(k / 24);
  const digit = D.digits[br][bc] === 1;
  if (t >= TM.digits && digit) {
    const t0 = TM.digits + bc * 0.014 + br * 0.006;
    st.flip = flipAngle(t, t0, 0.2);
    st.flipAxis = 1;
    st.back = PALETTE.chalk;
    if (t >= t0 + 0.2) {
      st.flip = 0;
      st.face = PALETTE.chalk;
      st.back = null;
    }
  }
  if (t >= TM.slide[0]) {
    const s = blockToStrip(k);
    const a = blockSlot(k), b = stripSlot(s.sc, s.sr);
    const mid = TM.slide[0] + (TM.slide[1] - TM.slide[0]) * 0.5;
    const ux = brandOut(prog(t, TM.slide[0], mid));
    const uy = brandOut(prog(t, mid, TM.slide[1]));
    st.x = lerp(a.x, b.x, ux);
    st.y = lerp(a.y, b.y, uy);
    st.z = 0;
    st.rz = 0;
    const undo = TM.slide[0] - 0.02;
    if (t >= undo && digit) {
      const t0 = undo + 0.012 * bc;
      st.flip = flipAngle(t, t0, 0.16);
      st.flipAxis = 1;
      st.face = PALETTE.chalk;
      st.back = null;
      if (st.flip > 0) {
        st.back = wallColor(i);
      }
      if (t >= t0 + 0.16) {
        st.flip = 0;
        st.face = wallColor(i);
        st.back = null;
      }
    }
    const hello = D.hello[s.sr][s.sc] === 1;
    const jp = D.japanese[s.sr][s.sc] === 1;
    if (t >= TM.hello && hello) {
      const t0 = TM.hello + s.sc * 0.009;
      st.flip = flipAngle(t, t0, 0.18);
      st.flipAxis = 1;
      st.face = wallColor(i);
      st.back = PALETTE.chalk;
      if (t >= t0 + 0.18) {
        st.flip = 0;
        st.face = PALETTE.chalk;
        st.back = null;
      }
    }
    if (t >= TM.japanese) {
      const t0 = TM.japanese + s.sc * 0.011 + s.sr * 0.004;
      const before = hello ? PALETTE.chalk : wallColor(i);
      const after = jp ? PALETTE.chalk : wallColor(i);
      st.flip = flipAngle(t, t0, 0.22);
      st.flipAxis = 0;
      st.face = before;
      st.back = after;
      if (t >= t0 + 0.22) {
        st.flip = 0;
        st.face = after;
        st.back = null;
      }
    }
  }
  if (t >= TM.qrBuild[0]) {
    const s = blockToStrip(k);
    const a = stripSlot(s.sc, s.sr);
    const q = qrAssign[i];
    const b = qrSlot(q);
    const delay = 0.12 * hash(i, 15) + 0.1 * (Math.abs(a.x - CENTER.x) / (24 * P));
    const u = brandOut(prog(t, TM.qrBuild[0] + delay, TM.qrBuild[0] + delay + 0.5));
    st.x = lerp(a.x, b.x, u);
    st.y = lerp(a.y, b.y, u);
    st.z = 120 * Math.sin(Math.PI * u) * (0.4 + 0.6 * hash(i, 16));
    const dark = qrDark(q % QS, Math.floor(q / QS));
    const target = dark ? PALETTE.orange : PALETTE.chalk;
    st.flip = Math.PI * smooth(clamp(u * 1.3));
    st.flipAxis = hash(i, 17) > 0.5 ? 1 : 0;
    st.face = st.face || wallColor(i);
    st.back = target;
    if (u >= 1) {
      st.flip = 0;
      st.face = target;
      st.back = null;
    }
    st.qr = true;
  }
  return st;
}

function qrPoolPose(i, t, st) {
  const q = qrAssign[i];
  const b = qrSlot(q);
  const row = Math.floor(q / QS);
  const t0 = TM.qrBuild[0] + 0.05 + (1 - row / (QS - 1)) * 0.55 + hash(i, 18) * 0.06;
  const dark = qrDark(q % QS, row);
  st.face = dark ? PALETTE.orange : PALETTE.chalk;
  st.back = null;
  st.flip = 0;
  st.qr = true;
  if (t < t0) return HIDE;
  const u = outQuart(prog(t, t0, t0 + 0.42));
  st.x = lerp(b.x + (hash(i, 19) - 0.5) * 200, b.x, u);
  st.y = lerp(PARK_Y + 300, b.y, u);
  st.z = lerp(260, 0, u);
  st.rx = (1 - u) * (2.2 + hash(i, 20) * 2);
  st.ry = (1 - u) * (hash(i, 21) - 0.5) * 2;
  st.rz = 0;
  return st;
}

const _st = {};
const _origin = { x: 0, y: 0, z: 0, qr: false };
export function tilePose(i, t) {
  if (t < TM.drop) {
    const st = preDropPose(i, t, _st);
    return st;
  }
  if (t >= TM.loop[0] + 1.0) return restPose(i);
  const pre = preDropPose(i, Math.min(t, TM.drop - 1e-4), _st);
  if (wmTaken[i]) return HIDE;
  let ox, oy, oz, qr;
  if (pre === HIDE || pre.hidden) {
    if (!flies(i)) return HIDE;
    ox = CENTER.x + (hash(i, 50) - 0.5) * 3000;
    oy = PARK_Y + 200 - hash(i, 51) * 500;
    oz = -500 + hash(i, 52) * 1300;
    qr = false;
  } else {
    ox = pre.x;
    oy = pre.y;
    oz = pre.z;
    qr = pre.qr;
  }
  const face = pre.face || (pre.hidden ? (hash(i, 53) < 0.2 ? PALETTE.orange : PALETTE.chalk) : wallColor(i));
  _origin.x = ox; _origin.y = oy; _origin.z = oz; _origin.qr = qr;
  const out = { face, back: null, flip: 0 };
  confettiState(i, t, _origin, out, null);
  if (out.y < -1600 && t > TM.drop + 0.5) return HIDE;
  return out;
}

const _rest = {};
function restPose(i) {
  _rest.x = gx(i % COLS);
  _rest.y = gy(Math.floor(i / COLS));
  _rest.z = 0;
  _rest.rx = _rest.ry = _rest.rz = 0;
  _rest.angle = undefined;
  _rest.flip = 0;
  _rest.face = null;
  _rest.back = null;
  return _rest;
}

const _vel = new THREE.Vector3();
const _cs = {};
const _qa = new THREE.Quaternion();
const _qb = new THREE.Quaternion();
export function wordmarkPose(k, t, outPos, outQuat) {
  if (t < TM.drop || t >= TM.loop[0] + 1.0) return false;
  const i = wmSource[k];
  const pre = preDropPose(i, TM.drop - 1e-4, _st);
  _origin.x = pre.x; _origin.y = pre.y; _origin.z = pre.z; _origin.qr = true;
  const tile = WORDMARK[k];
  const end = landEnd(k);
  const fly = tile.stop ? 0.9 : 0.75;
  const start = end - fly;
  if (t < start) {
    confettiState(i, t, _origin, _cs, null);
    outPos.set(_cs.x, _cs.y, _cs.z);
    quatFromState(_cs, outQuat);
    return true;
  }
  confettiState(i, start, _origin, _cs, _vel);
  quatFromState(_cs, _qa);
  const p0x = _cs.x, p0y = _cs.y, p0z = _cs.z;
  const u = clamp((t - start) / fly);
  const h00 = 2 * u ** 3 - 3 * u ** 2 + 1, h10 = u ** 3 - 2 * u ** 2 + u, h01 = -2 * u ** 3 + 3 * u ** 2, h11 = u ** 3 - u ** 2;
  const v1z = -260;
  outPos.set(
    h00 * p0x + h10 * _vel.x * fly + h01 * tile.wx,
    h00 * p0y + h10 * _vel.y * fly + h01 * tile.wy,
    h00 * p0z + h10 * _vel.z * fly + h01 * 0 + h11 * v1z * fly,
  );
  _qb.identity();
  outQuat.slerpQuaternions(_qa, _qb, smooth(clamp(u * 1.08)));
  if (t > end) {
    const s = t - end;
    const bounce = Math.exp(-s * 26) * Math.sin(s * 70) * 1.6;
    outPos.set(tile.wx, tile.wy, bounce);
    const wob = Math.exp(-s * 22) * Math.sin(s * 55) * 0.025;
    _e.set(wob * (hash(k, 60) - 0.5) * 2, wob * (hash(k, 61) - 0.5) * 2, 0);
    outQuat.setFromEuler(_e);
  }
  return true;
}

export function wordmarkVisible(t) {
  return t >= TM.drop && t < TM.loop[0] + 1.0;
}

export const LOOP_SWAP = TM.loop[0] + 1.0;
const swapHookTile = orangeOrder.reduce((best, i) => {
  const c = D.wall[i];
  const target = PALETTE.orange;
  const d = (c[1] - target.r) ** 2 + (c[2] - target.g) ** 2 + (c[3] - target.b) ** 2;
  const col = i % COLS, row = Math.floor(i / COLS);
  const central = Math.hypot(col - (COLS / 2 + 6), row - (ROWS / 2 - 0.5));
  const score = d * 40 + central * 0.002;
  return score < best.score ? { i, score } : best;
}, { i: orangeOrder[0], score: 1e9 }).i;

export const SWAP = {
  stop: WORDMARK.findIndex((t) => t.id === "stop-2"),
  hook: swapHookTile,
  hookPos: { x: gx(swapHookTile % COLS), y: gy(Math.floor(swapHookTile / COLS)) },
};

export function quatOf(st, q) {
  quatFromState(st, q);
  if (st.flip) {
    const flipQ = _q.setFromAxisAngle(st.flipAxis === 1 ? _axis.set(0, 1, 0) : _axis.set(1, 0, 0), st.flip);
    q.multiply(flipQ);
  }
  return q;
}

export const INFO = { N, COLS, ROWS, orange, background, QS, QR_CENTER, CENTER, WN, wallColor, gx, gy, QR_POOL_COUNT };
