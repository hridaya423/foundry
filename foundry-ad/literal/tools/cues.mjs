import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { openPage, root } from "./page.mjs";

const FPS = 60;
const { page, close } = await openPage({ draft: true });
const raw = await page.evaluate(async () => {
  const { tilePose, wordmarkPose, quatOf, WORDMARK, INFO, SWAP, LOOP_SWAP } = await import("/js/choreo.js");
  const { PLANS } = await import("/js/panel.js");
  const { camera } = await import("/js/camera.js");
  const THREE = await import("three");
  const TM = window.TM;
  const HZ = 240;
  const T = TM.end;
  const steps = Math.round(T * HZ);
  const q = new THREE.Quaternion();
  const q0 = new THREE.Quaternion();
  const departs = [];
  const arrivals = [];
  const pos = new Float32Array((steps + 1) * 3);
  const rot = new Float32Array((steps + 1) * 4);
  const vis = new Uint8Array(steps + 1);

  const angle = (a, b) => 2 * Math.acos(Math.min(1, Math.abs(rot[a * 4] * rot[b * 4] + rot[a * 4 + 1] * rot[b * 4 + 1] + rot[a * 4 + 2] * rot[b * 4 + 2] + rot[a * 4 + 3] * rot[b * 4 + 3])));
  const dist = (a, b) => Math.hypot(pos[a * 3] - pos[b * 3], pos[a * 3 + 1] - pos[b * 3 + 1], pos[a * 3 + 2] - pos[b * 3 + 2]);
  const HOLD = 24;
  function analyse(id) {
    let stopped = true;
    let still = 0;
    let leftAt = 0;
    for (let s = 1; s <= steps; s++) {
      if (!vis[s] || !vis[s - 1]) {
        stopped = false;
        still = 0;
        continue;
      }
      const moving = dist(s, s - 1) * HZ > 6 || angle(s, s - 1) * HZ > 0.12;
      if (moving) {
        if (stopped) {
          departs.push([s / HZ, id, pos[s * 3]]);
          leftAt = s - 1;
          stopped = false;
        }
        still = 0;
        continue;
      }
      if (stopped || ++still < HOLD) continue;
      stopped = true;
      const rest = s;
      let k = leftAt;
      while (k < rest && (dist(k, rest) > 0.75 || angle(k, rest) > 0.03)) k++;
      arrivals.push([k / HZ, id, pos[rest * 3], dist(leftAt, rest), angle(leftAt, rest)]);
    }
  }

  for (let i = 0; i < INFO.N; i++) {
    for (let s = 0; s <= steps; s++) {
      const st = tilePose(i, s / HZ);
      if (st.hidden) {
        vis[s] = 0;
        continue;
      }
      vis[s] = 1;
      quatOf(st, q);
      pos.set([st.x, st.y, st.z], s * 3);
      rot.set([q.x, q.y, q.z, q.w], s * 4);
    }
    analyse(`t${i}`);
  }
  const p = new THREE.Vector3();
  for (let k = 0; k < WORDMARK.length; k++) {
    for (let s = 0; s <= steps; s++) {
      if (!wordmarkPose(k, s / HZ, p, q0)) {
        vis[s] = 0;
        continue;
      }
      vis[s] = 1;
      pos.set([p.x, p.y, p.z], s * 3);
      rot.set([q0.x, q0.y, q0.z, q0.w], s * 4);
    }
    analyse(WORDMARK[k].stop ? `stop${k}` : `w${k}`);
  }

  const cam = [];
  for (let s = 0; s <= T * 60; s++) {
    const c = camera(s / 60);
    cam.push([c.tx, c.ty, c.dist, c.fov]);
  }
  return { TM, PLANS, departs, arrivals, cam, swap: LOOP_SWAP, wmCount: WORDMARK.length };
});
await close();

const { TM, PLANS, departs, arrivals, cam } = raw;
const frame = (t) => +(t * FPS).toFixed(2);
const panAt = (t, x) => {
  const c = cam[Math.min(cam.length - 1, Math.round(t * 60))];
  const half = c[2] * Math.tan((c[3] * Math.PI) / 360) * (16 / 9);
  return +Math.max(-1, Math.min(1, (x - c[0]) / half)).toFixed(2);
};
const events = [];
const push = (e) => events.push(e);

const names = ["remove", "calc", "translate", "qr", "confetti"];
TM.commands.forEach((cmd, c) => {
  const name = names[c];
  push({ f: frame(cmd.summon - 0.03), kind: "key", variant: "chord", weight: 0.9, id: `ui:${name}:chord` });
  const times = PLANS[c];
  const rate = times.length / Math.max(0.05, times[times.length - 1] - times[0]);
  const every = Math.max(1, Math.ceil(rate / 12));
  times.forEach((t, k) => {
    const ch = cmd.query[k];
    const wordStart = k === 0 || cmd.query[k - 1] === " ";
    if (!(wordStart || ch === " " || k % every === 0)) return;
    push({ f: frame(t), kind: "key", variant: ch === " " ? "space" : wordStart ? "word" : undefined, weight: wordStart ? 0.6 : 0.5, id: `ui:${name}:${ch === " " ? "space" : "key"}:${k}` });
  });
  push({ f: frame(cmd.enter - 0.07), kind: "key", variant: "return", weight: 1, id: `ui:${name}:return` });
});

const tileIndex = (id) => (id[0] === "t" ? Number(id.slice(1)) : -1);
function bin(list, from, to, kind, id, opts = {}) {
  const width = opts.width || 2 / FPS;
  let sel = list.filter((e) => e[0] >= from && e[0] < to && (!opts.filter || opts.filter(e)));
  if (opts.pick) {
    const by = new Map();
    for (const e of sel) if (!by.has(e[1]) || (opts.pick === "last") === e[0] > by.get(e[1])[0]) by.set(e[1], e);
    sel = [...by.values()];
  }
  if (!sel.length) return 0;
  const bins = new Map();
  for (const e of sel) {
    const b = Math.floor((e[0] - from) / width);
    if (!bins.has(b)) bins.set(b, []);
    bins.get(b).push(e);
  }
  const peak = Math.max(...[...bins.values()].map((v) => v.length));
  if (opts.lock) {
    const last = sel.reduce((m, e) => (e[0] > m[0] ? e : m), sel[0]);
    push({ f: frame(last[0]), kind: "lock", weight: 1, pan: panAt(last[0], last[2]), id: `${id}:lock` });
  }
  let n = 0;
  for (const [b, v] of [...bins.entries()].sort((a, b) => a[0] - b[0])) {
    const t = v.reduce((s, e) => s + e[0], 0) / v.length;
    const x = v.reduce((s, e) => s + e[2], 0) / v.length;
    push({ f: frame(t), kind, weight: +(0.35 + 0.85 * Math.sqrt(v.length / peak)).toFixed(2), pan: panAt(t, x), count: v.length, id: `${id}:${n++}`, ...(opts.variant ? { variant: opts.variant } : {}) });
  }
  return sel.length;
}

const counts = {};
const falls = departs.filter((e) => e[0] >= TM.cascade[0] && e[0] < TM.cascade[1] + 0.4).map((e) => e[0]).sort((a, b) => a - b);
counts.cascade = falls.length;
const fallAt = (q) => falls[Math.min(falls.length - 1, Math.floor(q * falls.length))];
push({ f: frame(falls[0]), kind: "cascade", weight: 1, dur: Math.round((fallAt(0.98) - falls[0]) * FPS), id: "tiles:cascade", peak: frame(fallAt(0.5)), end: frame(fallAt(0.98)) });
counts.square = bin(arrivals, TM.square[0], TM.square[1] + 0.5, "land", "tiles:square", { filter: (e) => e[3] > 8, width: 2 / FPS, pick: "last", lock: true });
counts.digits = bin(arrivals, TM.digits, TM.digits + 0.7, "flip", "tiles:flip:digits", { filter: (e) => e[3] < 8, width: 3 / FPS, pick: "last" });
counts.undo = bin(arrivals, TM.slide[0] - 0.1, TM.slide[0] + 0.35, "flip", "tiles:flip:undo", { filter: (e) => e[3] < 8, width: 2 / FPS, pick: "last" });
counts.slide = bin(arrivals, TM.slide[0], TM.slide[1] + 0.3, "land", "tiles:slide", { filter: (e) => e[3] > 30, width: 2 / FPS, variant: "slide", pick: "last" });
counts.hello = bin(arrivals, TM.hello, TM.hello + 0.6, "flip", "tiles:flip:hello", { filter: (e) => e[3] < 8, width: 3 / FPS, pick: "last" });
counts.japanese = bin(arrivals, TM.japanese, TM.japanese + 0.9, "flip", "tiles:flip:jp", { filter: (e) => e[3] < 8, width: 4 / FPS, pick: "last" });
counts.qrLeave = bin(departs, TM.qr.enter - 0.1, TM.qrBuild[0] + 0.3, "lift", "tiles:qr:lift", { width: 3 / FPS });
counts.qr = bin(arrivals, TM.qrBuild[0], TM.qrBuild[1] + 0.4, "land", "tiles:qr:land", { width: 4 / FPS, pick: "last", lock: true });
counts.wordmark = bin(arrivals, TM.land[0] - 0.2, TM.land[1] + 0.2, "land", "tiles:wm:land", { filter: (e) => e[1][0] === "w", width: 6 / FPS, variant: "light", pick: "first" });
const stops = arrivals.filter((e) => e[1].startsWith("stop"));
const firstStop = new Map();
for (const e of stops) if (!firstStop.has(e[1]) || e[0] < firstStop.get(e[1])) firstStop.set(e[1], e[0]);
const period = Math.max(...firstStop.values());
push({ f: frame(period), kind: "land", weight: 1.6, id: "logo:period" });
push({ f: frame(TM.line), kind: "caption", weight: 0.6, id: "logo:caption:0" });
push({ f: frame(TM.line + 0.5), kind: "caption", weight: 0.4, id: "logo:caption:1" });
push({ f: frame(TM.drop), kind: "drop", weight: 1.8, id: "fx:drop" });
counts.burst = departs.filter((e) => Math.abs(e[0] - TM.drop) < 0.05).length;

const speed = cam.map((c, s) => (s ? Math.abs(Math.log(c[2]) - Math.log(cam[s - 1][2])) * 60 + Math.hypot(c[0] - cam[s - 1][0], c[1] - cam[s - 1][1]) / c[2] * 60 : 0));
function whoosh(from, to, id) {
  let best = from * 60;
  for (let s = Math.round(from * 60); s <= Math.round(to * 60); s++) if (speed[s] > speed[best]) best = s;
  push({ f: frame(best / 60), kind: "whoosh", weight: +Math.min(2, speed[best] / 4).toFixed(2), dur: Math.round((to - from) * FPS), apexFrac: +((best / 60 - from) / (to - from)).toFixed(2), id, peak: +speed[best].toFixed(2) });
}
whoosh(TM.loop[0], raw.swap - 3 / 60, "cam:dive:in");
whoosh(raw.swap + 3 / 60, TM.loop[1], "cam:dive:out");
whoosh(TM.square[0], TM.square[1] + 0.5, "cam:push:square");
whoosh(TM.drop, TM.land[0] + 0.4, "cam:push:confetti");
push({ f: frame(raw.swap), kind: "tock", weight: 0.7, id: "loop:swap" });

events.sort((a, b) => a.f - b.f);
const acts = {
  intro: [0, TM.cascade[0]],
  remove: [TM.cascade[0], TM.calc.summon],
  calc: [TM.calc.summon, TM.translate.summon],
  translate: [TM.translate.summon, TM.qr.summon],
  qr: [TM.qr.summon, TM.confetti.summon],
  confetti: [TM.confetti.summon, TM.land[0]],
  logo: [TM.land[0], TM.loop[0]],
  loop: [TM.loop[0], TM.end],
};
const out = {
  _doc: "Generated by tools/cues.mjs from the picture code (tile poses sampled at 240 Hz). Do not edit by hand.",
  fps: FPS,
  bpm: 120,
  total: Math.round(TM.end * FPS),
  loop: true,
  acts: Object.fromEntries(Object.entries(acts).map(([k, [a, b]]) => [k, { from: frame(a), dur: frame(b - a) }])),
  cue: { drop: frame(TM.drop), period: frame(period), swap: frame(raw.swap), line: frame(TM.line) },
  counts,
  events,
};
await mkdir(join(root, "out"), { recursive: true });
await writeFile(join(root, "out/cues.json"), JSON.stringify(out, null, 1));
console.log(JSON.stringify(counts), "events", events.length, "period", period.toFixed(3));
