// Sparks: one particle system for the whole film. Every particle is a closed-form function of composition time
// (birth, burst velocity, gravity, linear drag), so any frame can be drawn alone. gl.js draws each one as a streak
// over the shutter, coloured by body(T) as it cools.
(function () {
  const { hash } = window.L;
  const SH = 1 / 60;                     // one shutter: the streak each spark smears
  // position after age a: v' = g - k v  =>  p = vt a + (v0 - vt)(1 - e^-ka)/k, vt = g/k (terminal velocity)
  const at = (a, vx, vy, g, k) => {
    const e = (1 - Math.exp(-k * a)) / k, vt = g / k;
    return [vx * e, vt * a + (vy - vt) * e];
  };
  const R = (e, k, j) => hash(e.seed * 7919 + k * 131 + j * 17);
  const span = ([a, b], r) => a + (b - a) * r;

  // e: { seed, t0, n, x, y (emitter, in the map's space), spread (birth jitter s), perim (k, r) -> [dx, dy] (spawn offset),
  //      dir (rad, screen: -PI/2 is up), cone (rad), speed [a, b], life [a, b], T0 [a, b], r [a, b] (px), E [a, b],
  //      g (px/s^2, + falls), drag (1/s), bokeh (0|1), grow (radius growth /s), wob (px), map (x, y) -> [px, py, scale] | null }
  // pushes [ax, ay, bx, by, r, T, E, kind] per live particle into out
  function emit(out, t, e) {
    const life0 = e.life[1];
    if (t < e.t0 || t > e.t0 + (e.spread || 0) + life0) return;
    for (let k = 0; k < e.n; k++) {
      const birth = e.t0 + (e.spread || 0) * R(e, k, 1), age = t - birth, life = span(e.life, R(e, k, 2));
      if (age < 0 || age > life) continue;
      const ang = e.dir + (R(e, k, 3) - 0.5) * e.cone, sp = span(e.speed, R(e, k, 4) ** 0.7);
      const vx = Math.cos(ang) * sp, vy = Math.sin(ang) * sp, g = e.g * (0.85 + 0.3 * R(e, k, 5)), kd = e.drag * (0.7 + 0.6 * R(e, k, 6));
      const [ox, oy] = e.perim ? e.perim(k, R(e, k, 7)) : [0, 0];
      const wob = e.wob || 0, wf = 3 + 4 * R(e, k, 8), wp = R(e, k, 9) * 6.28;
      const pos = (a) => { const [dx, dy] = at(a, vx, vy, g, kd); return [e.x + ox + dx + wob * Math.sin(a * wf + wp), e.y + oy + dy]; };
      const p1 = pos(age), p0 = pos(Math.max(0, age - SH));
      const s1 = e.map ? e.map(p1[0], p1[1]) : [p1[0], p1[1], 1];
      if (!s1) continue;
      const s0 = e.map ? e.map(p0[0], p0[1]) || s1 : [p0[0], p0[1], 1];
      // cools along one curve: white, orange, red, gone; the first frame flashes as it tears free
      const T = span(e.T0, R(e, k, 10)) * Math.exp(-age / (life / 2.3)) * (age < 0.03 ? 1.12 : 1);
      if (T < 0.12) continue;
      let r = span(e.r, R(e, k, 11) ** 2) * s1[2] * (1 + (e.grow || 0) * age);
      let E = span(e.E, R(e, k, 12)) * Math.min(1, s1[2] * 1.4 + 0.3);
      if (r < 0.55) { E *= (r / 0.55) ** 2; r = 0.55; }              // sub-pixel: dimmer, never thinner than the sampling
      const len = Math.hypot(s1[0] - s0[0], s1[1] - s0[1]);
      if (!e.bokeh) E *= 0.3 + 0.7 * (2.4 * r) / (len + 2.4 * r);      // a long streak spreads the same light thinner
      if (s1[0] < -60 || s1[0] > 1980 || s1[1] < -60 || s1[1] > 1140) continue;
      out.push(s0[0], s0[1], s1[0], s1[1], r, T, E, e.bokeh ? 1 : 0);
    }
  }
  // slow embers rising in a heat column: each slot respawns on its own cycle
  function column(out, t, c) {
    if (t < c.t0 || t > c.t1) return;
    for (let k = 0; k < c.n; k++) {
      const life = 1.4 + 1.2 * hash(c.seed * 31 + k), off = hash(c.seed * 37 + k * 3), cyc = Math.floor((t - c.t0) / life + off);
      const birth = c.t0 + (cyc - off) * life;
      if (birth < c.t0 || birth > c.t1 - 0.3) continue;
      const r = (j) => hash(c.seed * 41 + k * 59 + cyc * 7 + j);
      emit(out, t, { seed: c.seed * 977 + k * 61 + cyc, t0: birth, n: 1, x: c.x + (r(1) - 0.5) * c.w, y: c.y + (r(2) - 0.5) * c.h,
        dir: -Math.PI / 2, cone: 0.7, speed: [50, 160], life: [life * 0.9, life], T0: [0.75, 1.0], r: [0.9, 1.6], E: [0.8, 1.4],
        g: -60, drag: 1.2, wob: 10, map: c.map });
    }
  }
  window.SPARKS = { emit, column };
})();
