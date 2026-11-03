// Shared helpers. Everything here is a pure function of composition time.
(function () {
  const FPS = 60;

  function rng(seed) {
    let a = seed >>> 0;
    return function () {
      a = (a + 0x6d2b79f5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function hash(n) {
    n = (Math.imul(n | 0, 374761393) + 668265263) | 0;
    n = Math.imul(n ^ (n >>> 13), 1274126177);
    return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
  }

  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, p) => a + (b - a) * p;
  const prog = (t, a, b) => clamp((t - a) / (b - a));
  const smooth = (p) => p * p * (3 - 2 * p);
  const ease = {
    outCubic: (p) => 1 - Math.pow(1 - p, 3),
    inCubic: (p) => p * p * p,
    outExpo: (p) => (p >= 1 ? 1 : 1 - Math.pow(2, -10 * p)),
    inExpo: (p) => (p <= 0 ? 0 : Math.pow(2, 10 * p - 10)),
    inOutExpo: (p) => (p <= 0 ? 0 : p >= 1 ? 1 : p < 0.5 ? Math.pow(2, 20 * p - 10) / 2 : (2 - Math.pow(2, -20 * p + 10)) / 2),
    outQuart: (p) => 1 - Math.pow(1 - p, 4),
    inOutCubic: (p) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2),
    outBack: (p, s = 1.7) => 1 + (s + 1) * Math.pow(p - 1, 3) + s * Math.pow(p - 1, 2),
  };
  const frame = (t) => Math.floor(t * FPS + 1e-6);
  const snap = (t) => Math.round(t * FPS) / FPS;

  // Integrate a speed curve s(t) into warped time; table at 1/1200 s so seeks are exact and cheap.
  function warp(t0, t1, speed) {
    const dt = 1 / 1200;
    const n = Math.ceil((t1 - t0) / dt) + 1;
    const tab = new Float64Array(n);
    for (let i = 1; i < n; i++) tab[i] = tab[i - 1] + speed(t0 + (i - 0.5) * dt) * dt;
    return (t) => {
      if (t <= t0) return 0;
      const x = (t - t0) / dt;
      const i = Math.min(n - 2, Math.floor(x));
      return tab[i] + (tab[i + 1] - tab[i]) * (x - i);
    };
  }

  const GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#%&*+=/<>";
  // Scramble from one word to another: letters resolve left to right; unresolved slots cycle per frame.
  function scramble(from, to, p, seed) {
    const n = Math.max(from.length, to.length);
    const f = Math.floor(p * 40);
    let s = "";
    for (let i = 0; i < n; i++) {
      const resolve = (i + 1) / (n + 1);
      if (p >= resolve + 0.12 || p >= 1) s += to[i] || "";
      else if (p < resolve * 0.35) s += from[i] || "";
      else s += GLYPHS[Math.floor(hash(seed * 131 + i * 17 + f) * GLYPHS.length)];
    }
    return s.replace(/\s+$/, "");
  }

  function typeOn(text, t, t0, cps) {
    const n = Math.floor(clamp((t - t0) * cps, 0, text.length));
    return text.slice(0, n);
  }

  // Global clock: a plain object GSAP tweens from 0 to duration; its setter draws every registered layer.
  // The master renders at 240fps and blends sub-frames into 60fps, so discrete layers (type, scrambles, layout
  // steps, grain) get time snapped to the 60fps frame and stay crisp; only continuous layers see sub-frame time.
  const renderers = [];
  const clock = {
    _t: 0,
    get t() { return this._t; },
    set t(v) {
      this._t = v;
      const q = snap(v);
      for (const r of renderers) r.fn(r.continuous ? v : q);
    },
  };

  function deferred() {
    let resolve;
    const p = new Promise((r) => (resolve = r));
    p.resolve = resolve;
    return p;
  }

  // every cut lands half a frame before its frame so clip windows, sets and sub-frame blends agree
  const cut = (t) => (Math.round(t * FPS) - 0.5) / FPS;

  // Scene windows on the beat grid, cut-snapped: PLAN.open = [t0, t1], ...
  const T = window.FD.timing;
  const PLAN = { beat: T.beat, strike: cut(T.strike), first: cut(T.first), end: cut(T.end), order: [] };
  {
    let b = Math.round(T.first / T.beat);
    for (const s of T.scenes) {
      PLAN[s.id] = [cut(b * T.beat), cut((b + s.beats) * T.beat)];
      PLAN.order.push(s.id);
      b += s.beats;
    }
  }

  window.L = { FPS, rng, hash, clamp, lerp, prog, smooth, ease, frame, snap, cut, warp, scramble, typeOn, clock, renderers,
    on: (fn, opts = {}) => renderers.push({ fn, continuous: !!opts.continuous }), deferred, glReady: deferred(), PLAN };
})();
